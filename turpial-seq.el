;;; turpial-seq.el --- Asynchronous sequencer for SuperCollider in Elisp -*- lexical-binding: t; -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Author: Numa Tortolero
;; Version: 0.1.1
;; Keywords: supercollider, synthdef, dsl
;; URL: https://github.com/superguaricho/turpial
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;;  Commentary:
;;  Asynchronous sequencer for SuperCollider in Elisp.
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
(require 'turpial-dsl)

(defvar turpial-seq-stop-flag nil
  "Internal flag to stop the sequencer.")

(defvar turpial-seq-current-timer nil
  "Current timer for the running sequence.")

;;;###autoload
(defun turpial-seq-stop ()
  "Stop the currently running sequence."
  (interactive)
  (setq turpial-seq-stop-flag t)
  (when turpial-seq-current-timer
    (cancel-timer turpial-seq-current-timer)
    (setq turpial-seq-current-timer nil))
  (message "🛑 Sequencer stopped."))

(defun turpial-seq--play-step (synth-name pattern index)
  "Play one step of the PATTERN and schedule the next one."
  (unless turpial-seq-stop-flag
    (let* ((step (nth (% index (length pattern)) pattern))
            (dur (or (plist-get step :dur) 0.25))
            ;; Extract all other parameters for the synth
            (params (cl-loop for (k v) on step by #'cddr
                      unless (eq k :dur)
                      append (list k v))))

      ;; 1. Play the synth
      (apply #'turpial-dsl-synth synth-name params)

      ;; 2. Schedule the next step
      (setq turpial-seq-current-timer
        (run-at-time dur nil #'turpial-seq--play-step synth-name pattern (1+ index))))))

;;;###autoload
(defun turpial-seq-play (synth-name pattern)
  "Start playing a PATTERN with SYNTH-NAME.
PATTERN is a list of plists, e.g., '((:freq 55 :dur 0.25) (:freq 66 :dur 0.5))."
  (interactive)
  (turpial-seq-stop) ;; Ensure only one sequence at a time
  (setq turpial-seq-stop-flag nil)
  (turpial-seq--play-step synth-name pattern 0)
  (message "🎶 Sequencer started: %s" synth-name))

(provide 'turpial-seq)
