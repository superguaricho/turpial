;;; turpial.el --- DSL in Elisp to generate SuperCollider patterns  -*- lexical-binding: t; -*-
;;
;; Filename: turpial.el
;; Description: DSL in Elisp to generate SuperCollider patterns
;; Author: Numa Tortolero
;; Version: 0.1.1
;; Package-Requires: ((emacs "27.1") (osc "0.4") (sclang))
;; URL: https://github.com/superguaricho/turpial
;; Keywords: Emacs, SuperCollider, SuperDirt, OSC, TidalCycles
;; Compatibility: Emacs 27.1 and later
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;   This Emacs Lisp file provides a simple DSL to create and manage
;;   SuperCollider patterns (similar to TidalCycles) directly from Emacs.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Code:

(add-to-list 'load-path
  (file-name-directory (or load-file-name buffer-file-name)))

(require 'turpial-dsl)
(require 'turpial-osc)

(require 'turpial-scsynth)
(require 'turpial-seq)

(require 'osc)
(require 'cl-lib)

;; --- Constants ---
(defvar silence "silence" "Constant to represent an empty pattern.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Configuration & State
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar turpial-dirt-client nil)
(defvar turpial-cps 1.0 "Cycles per second.")
(defvar turpial-orbits (make-hash-table :test 'equal))
(defvar turpial-current-params (make-hash-table :test 'equal))
(defvar turpial-timer nil)
(defvar turpial-latency 0.1 "Latency offset for stability.")

(defvar turpial--last-tick-cycle 0.0)
(defvar turpial--start-time nil)

(defun turpial-get-client ()
  (unless (and turpial-dirt-client (process-live-p turpial-dirt-client))
    (setq turpial-dirt-client (osc-make-client "127.0.0.1" 57120)))
  turpial-dirt-client)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Parser
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun turpial-parse (pattern-str)
  (if (or (null pattern-str) (string= pattern-str "silence"))
    nil
    (let* ((parts (split-string pattern-str "[ \t]+" t))
            (total (length parts))
            (dur (/ 1.0 (float (max 1 total))))
            (events '()))
      (cl-loop for part in parts for i from 0
        do (let ((sample part) (count 1))
             (when (string-match "\\([^*]+\\)\\*\\([0-9]+\\)" part)
               (setq sample (match-string 1 part)
                 count (string-to-number (match-string 2 part))))
             (unless (string= sample "~")
               (let ((sub-dur (/ dur (float count))))
                 (cl-loop for j from 0 below count
                   do (push (list (+ (* i dur) (* j sub-dur)) sample) events))))))
      (nreverse events))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Scheduler & Playback
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun turpial-set-cps (new-cps)
  (interactive "nCPS: ")
  (setq turpial-cps (float new-cps))
  (message "⏱ Tempo: %f CPS" new-cps))

(defun turpial-init-groups ()
  "Ensure orbit groups (1001-1016) exist on the SC server."
  (let ((client (turpial-osc-get-client)))
    (cl-loop for i from 1 to 16 do
      (osc-send-message client "/g_new" (+ 1000 i) 1 0))))

(defun turpial-send (orbit-id sample)
  (let* ((dirt-client (turpial-get-client))
          (sc-client (turpial-osc-get-client))
          (orbit-group (+ 1000 orbit-id))
          (orbit-params (gethash orbit-id turpial-current-params))
          (is-elisp-synth (and (boundp 'turpial-dsl--registry)
                            (member sample turpial-dsl--registry))))
    (if is-elisp-synth
      (let* ((node-id (+ 20000 (random 10000)))
              (params '()))
        (cl-loop for (k v) on orbit-params by #'cddr
          do (setq params (append params (list (substring (symbol-name k) 1)
                                           (if (numberp v) (float v) v)))))
        ;; Launch synth inside its orbit group (Target: orbit-group, Action: 1 (Add to tail))
        (apply #'turpial-scsynth-send sc-client "/s_new" sample node-id 1 orbit-group params))
      (let ((msg (list "/dirt/play" "s" sample "orbit" orbit-id "cps" (float turpial-cps))))
        (cl-loop for (k v) on orbit-params by #'cddr
          do (let ((key-str (substring (symbol-name k) 1)))
               (setq msg (append msg (list key-str (if (numberp v) (float v) v))))))
        (unless (member "gain" msg) (setq msg (append msg (list "gain" 1.0))))
        (when (and dirt-client (process-live-p dirt-client))
          (apply #'turpial-scsynth-send dirt-client msg))))))

(defun turpial--tick (&optional _unused)
  (when (and turpial--start-time turpial-timer)
    (let* ((now (float-time))
            (look-ahead 0.3)
            (t1 turpial--last-tick-cycle)
            (t2 (* (- (+ now look-ahead) turpial--start-time) turpial-cps)))
      (maphash
        (lambda (orbit-name events)
          (let ((orbit-id (string-to-number (substring orbit-name 1))))
            (dolist (event events)
              (let* ((offset (car event))
                      (sample (cadr event))
                      (f1 (floor t1))
                      (f2 (floor t2)))
                (cl-loop for c from f1 to f2
                  do (let ((abs-cycle (+ c offset)))
                       (when (and (>= abs-cycle t1) (< abs-cycle t2))
                         (let* ((event-time (+ turpial--start-time
                                              (/ abs-cycle (float turpial-cps))))
                                 (delay (- event-time now)))
                           (run-at-time (+ delay turpial-latency) nil
                             #'turpial-send orbit-id sample)))))))))
        turpial-orbits)
      (setq turpial--last-tick-cycle t2))))

(defun turpial-start ()
  (unless turpial-timer
    (turpial-init-groups)
    (setq turpial--start-time (float-time))
    (setq turpial--last-tick-cycle 0.0)
    (setq turpial-timer (run-at-time 0 0.05 #'turpial--tick))
    (message "🌊 Engine started.")))

(defun turpial-set (id pattern &rest params)
  (let ((orbit-name (format "d%d" id))
         (orbit-group (+ 1000 id)))
    (if (or (null pattern) (equal pattern "silence"))
      (progn
        (remhash orbit-name turpial-orbits)
        (remhash id turpial-current-params)
        ;; Silence logic for Elisp synths:
        (let ((client (turpial-osc-get-client)))
          ;; 1. Send gate 0 to the entire orbit group for a smooth release
          (osc-send-message client "/n_set" orbit-group "gate" 0.0)
          ;; 2. Optional: Free all nodes in the group after a short delay (e.g., 0.5s)
          (run-at-time 0.5 nil (lambda (cl grp) (osc-send-message cl "/g_freeAll" grp)) client orbit-group))
        (message "🔇 %s silenced." orbit-name))
      (puthash orbit-name (turpial-parse pattern) turpial-orbits)
      (puthash id params turpial-current-params)
      (turpial-start)
      (message "🎵 %s: %s" orbit-name pattern))))

;; API Commands
(defun d1 (p &rest args) (interactive "sP: ") (apply #'turpial-set 1 p args))
(defun d2 (p &rest args) (interactive "sP: ") (apply #'turpial-set 2 p args))
(defun d3 (p &rest args) (interactive "sP: ") (apply #'turpial-set 3 p args))
(defun d4 (p &rest args) (interactive "sP: ") (apply #'turpial-set 4 p args))
(defun d5 (p &rest args) (interactive "sP: ") (apply #'turpial-set 5 p args))
(defun d6 (p &rest args) (interactive "sP: ") (apply #'turpial-set 6 p args))
(defun d7 (p &rest args) (interactive "sP: ") (apply #'turpial-set 7 p args))
(defun d8 (p &rest args) (interactive "sP: ") (apply #'turpial-set 8 p args))

(defun stop ()
  (interactive)
  (when turpial-timer (cancel-timer turpial-timer) (setq turpial-timer nil))
  (setq turpial--start-time nil)
  (message "🔇 Stopped."))

(defun hush ()
  (interactive)
  (stop)
  (clrhash turpial-orbits)
  (clrhash turpial-current-params)
  (let ((client (turpial-get-client))
         (sc-client (turpial-osc-get-client)))
    ;; 1. SuperDirt stop
    (when (and client (process-live-p client))
      (turpial-scsynth-send client "/dirt/stopAll"))
    ;; 2. Elisp synths stop (all orbits 1001-1016)
    (cl-loop for i from 1 to 16 do
      (osc-send-message sc-client "/n_set" (+ 1000 i) "gate" 0.0)
      (run-at-time 0.2 nil (lambda (c g) (osc-send-message c "/g_freeAll" g)) sc-client (+ 1000 i))))
  (message "🤫 Hush..."))

;; (setq turpial-latency 0.1)
;; (setq turpial-cps 1.0)

(provide 'turpial)
;;; turpial.el ends here
