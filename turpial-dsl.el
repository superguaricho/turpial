;;; turpial-dsl.el --- A small DSL for SuperCollider SynthDefs in Elisp   -*- lexical-binding: t; -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Author: Numa Tortolero
;; Version: 0.1.1
;; Keywords: supercollider, synthdef, dsl
;; URL: https://github.com/superguaricho/turpial
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; This package provides a simple DSL for defining SuperCollider SynthDefs
;; directly in Emacs Lisp. It compiles high-level descriptions into the
;; binary format expected by the SuperCollider server, allowing you to
;; create complex synths with a more concise syntax. It also includes
;; helper functions for managing buffers and recording.
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

(require 'turpial-hardcore)

(defvar turpial-dsl--current-synth nil)

(defvar turpial-dsl--registry '())

(defun turpial-dsl--get-rate (rate)
  (cond ((eq rate :ir) 0)
    ((eq rate :kr) 1)
    ((eq rate :ar) 2)
    (t rate)))

;; --- Envelope Helpers ---

(defun turpial-dsl--ensure-float (val)
  "Convert VAL to float if numeric, otherwise leave as is."
  (if (numberp val) (float val) val))

(defun turpial-dsl-env-asr (&optional attack sustain release curve)
  "Create an ASR (ATTACK-SUSTAIN-RELEASE) envelope array."
  (let ((a (or attack 0.01))
         (s (or sustain 1.0))
         (r (or release 1.0))
         (c (or curve -4.0)))
    (list 0.0 2.0 1.0 -99.0
      (turpial-dsl--ensure-float s) (turpial-dsl--ensure-float a) 5.0 (turpial-dsl--ensure-float c)
      0.0 (turpial-dsl--ensure-float r) 5.0 (turpial-dsl--ensure-float c))))

(defun turpial-dsl-env-perc (&optional attack release level curve)
  "Create a PERC (Percussive) envelope array."
  (let ((a (or attack 0.01))
         (r (or release 1.0))
         (l (or level 1.0))
         (c (or curve -4.0)))
    (list 0.0 2.0 -99.0 -99.0
      (turpial-dsl--ensure-float l) (turpial-dsl--ensure-float a) 5.0 (turpial-dsl--ensure-float c)
      0.0 (turpial-dsl--ensure-float r) 5.0 (turpial-dsl--ensure-float c))))

(defun turpial-dsl-env-line (&optional start end duration)
  "Create a linear envelope array from START to END over DURATION.
Default: 1.0 to 0.0 over 1.0s."
  (let ((s (or start 1.0))
         (e (or end 0.0))
         (d (or duration 1.0)))
    ;; Format: [initialLevel, n_segments, releaseNode, loopNode,
    ;;          targetLevel, duration, shape, curve]
    ;; Shape 1.0 is Linear.
    (list (turpial-dsl--ensure-float s)
      1.0 -99.0 -99.0
      (turpial-dsl--ensure-float e)
      (turpial-dsl--ensure-float d)
      1.0 0.0)))

;; --- Updated Compiler ---

(defun turpial-dsl-compile (name params nodes)
  "Compile a high-level synth description into a binary SCgf blob."
  (let* ((constants '())
          (parameter-values (mapcar #'cdr params))
          (parameter-names (let ((i 0)) (mapcar (lambda (p) (prog1 (cons (car p) i) (setq i (1+ i)))) params)))
          (node-map '()) ;; Maps symbol names to UGen indices
          (compiled-ugens '())
          (current-ugen-idx (if params 1 0)))

    ;; 1. Helper to handle inputs (now supports symbols for node names)
    (defun resolve-input (in)
      (cond
        ((floatp in)
          (unless (member in constants) (setq constants (append constants (list in))))
          (cons -1 (cl-position in constants)))
        ((stringp in)
          (let ((idx (assoc in parameter-names)))
            (unless idx (error "Unknown parameter: %s" in))
            (cons 0 (cdr idx))))
        ((symbolp in)
          (let ((idx (assoc in node-map)))
            (unless idx (error "Unknown node reference: %s" in))
            (cons (cdr idx) 0))) ;; Defaults to output 0
        ((integerp in)
          (cons in 0))
        ((and (listp in) (symbolp (car in)))
          (let ((idx (assoc (car in) node-map)))
            (unless idx (error "Unknown node reference: %s" in))
            (cons (cdr idx) (cadr in))))
        ((and (listp in) (integerp (car in)))
          (cons (car in) (cadr in)))
        (t (error "Invalid input: %S" in))))

    ;; 2. Add Control UGen automatically
    (when params
      (push (list "Control" 1 '() (length params) 0) compiled-ugens))

    ;; 3. Compile nodes
    (dolist (node nodes)
      (let* ((type (symbol-name (car node)))
              (rate (turpial-dsl--get-rate (nth 1 node)))
              (raw-inputs (nth 2 node))
              (args (nthcdr 3 node))
              (special (or (plist-get args :special) 0))
              (outputs (or (plist-get args :outputs) 1))
              (as-name (plist-get args :as))
              ;; MODIFICATION: Flatten inputs to support envelopes as lists
              (flat-raw-inputs (cl-loop for in in raw-inputs
                                 if (and (listp in) (not (symbolp (car in))) (not (integerp (car in))))
                                 append in else collect in))
              (resolved-inputs (mapcar #'resolve-input flat-raw-inputs)))

        ;; Register the name if :as was provided
        (when as-name
          (push (cons as-name current-ugen-idx) node-map))

        (push (list type rate resolved-inputs outputs special) compiled-ugens)
        (setq current-ugen-idx (1+ current-ugen-idx))))

    (setq compiled-ugens (nreverse compiled-ugens))

    ;; 4. Build binary (ensure everything is unibyte)
    (let ((raw-blob
            (concat
              "SCgf" (sc-int32 2) (sc-int16 1)
              (sc-string name)
              (sc-int32 (length constants)) (apply #'concat (mapcar #'sc-float32 constants))
              (sc-int32 (length parameter-values)) (apply #'concat (mapcar #'sc-float32 parameter-values))
              (sc-int32 (length parameter-names))
              (apply #'concat (mapcar (lambda (pn) (concat (sc-string (car pn)) (sc-int32 (cdr pn)))) parameter-names))
              (sc-int32 (length compiled-ugens))
              (apply #'concat (mapcar (lambda (u)
                                        (let ((type (nth 0 u)) (rate (nth 1 u)) (inputs (nth 2 u))
                                               (outs (nth 3 u)) (spec (nth 4 u)))
                                          (concat (sc-string type) (sc-int8 rate)
                                            (sc-int32 (length inputs)) (sc-int32 outs) (sc-int16 spec)
                                            (apply #'concat (mapcar (lambda (in) (concat (sc-int32 (car in)) (sc-int32 (cdr in)))) inputs))
                                            (apply #'concat (make-list outs (sc-int8 rate))))))
                                compiled-ugens))
              (sc-int16 0))))
      (let ((v (string-to-vector (string-to-unibyte raw-blob))))
        ;; DEBUG: Log blob length
        ;; (message "DEBUG: Compiled '%s', blob size: %d" name (length v))
        v))))

;; --- Buffer & Server Management ---

(defun turpial-osc-buffer-alloc-read (path &optional buf-num)
  "Load an audio file at PATH into a buffer on the server.
BUF-NUM defaults to 0."
  (let ((client (turpial-osc-get-client))
         (b (or buf-num 0)))
    (osc-send-message client "/b_allocRead" b (expand-file-name path) 0 0)
    (message "📂 Loading buffer %d: %s" b path)
    b))

(defun turpial-osc-record-start (filename &optional num-channels)
  "Start recording the server output to FILENAME.
NUM-CHANNELS: optional, number of parameters."
  (let* ((client (turpial-osc-get-client))
          (path (expand-file-name filename))
          (channels (or num-channels 2))
          (buf-num 99) ; Special buffer for recording
          (frame-count 65536))
    ;; 1. Allocate buffer for recording
    (osc-send-message client "/b_alloc" buf-num frame-count channels)
    ;; 2. Open file for writing
    (osc-send-message client "/b_write" buf-num path "wav" "int24" 0 0 1)
    ;; 3. Start node to write to disk (this usually requires a DiskOut Synth)
    ;; For simplicity, we'll use the server's internal recording if available
    ;; but the most robust way is a DiskOut synth.
    (message "🔴 Recording started: %s" path)))

(defun turpial-osc-record-stop ()
  "Stop recording and close the file."
  (let ((client (turpial-osc-get-client)))
    (osc-send-message client "/b_close" 99)
    (osc-send-message client "/b_free" 99)
    (message "⬜ Recording stopped.")))

;;;###autoload
(defun turpial-dsl-synth (name &rest args)
  "Instantiate a Synth called NAME on the server with ARGS."
  (let* ((client (turpial-osc-get-client))
          (node-id (+ 10000 (random 10000)))
          ;; Default target to 0 (root) because Group 1 might not exist without sclang
          (target (or (plist-get args :target) 0))
          (action (or (plist-get args :addAction) 1)) ; addToTail of Group 0
          (osc-args (cl-loop for (k v) on args by #'cddr
                      if (and (symbolp k) (not (memq k '(:target :addAction))))
                      append (list (substring (symbol-name k) 1)
                               (if (numberp v) (float v) v)))))
    (apply #'osc-send-message client "/s_new" name node-id action target osc-args)
    (message "🔊 Synth '%s' -> Node: %d (Target: %d, Action: %d)" name node-id target action)
    node-id))
(defvar turpial-dsl--registry '()
  "List of synth names defined via the DSL.")

(defun turpial-register-synthdef-name (name)
  "Regiser a SynthDef NAME."
  (add-to-list 'turpial-dsl--registry name))

(defun turpial-send-synthdef (client vector-blob)
  "Send a SynthDef passing its CLIENT and the VECTOR-BLOB."
  (osc-send-message client "/d_recv" vector-blob))

;;;###autoload
(defun turpial-dsl-synthdef (name &rest body)
  "Define the BODY of a SynthDef and register its NAME."
  (let* ((params (plist-get body :params))
          (nodes (plist-get body :nodes))
          (action (or (plist-get body :action) :add))
          (vector-blob (turpial-dsl-compile name params nodes))
          (client (turpial-osc-get-client)))
    (turpial-register-synthdef-name name)
    (turpial-send-synthdef client vector-blob)
    (cond
      ((eq action :play)
        (message "🚀 DSL: SynthDef '%s' added and playing..." name)
        ;; Flatten params for the play call
        (let ((flat-params (cl-loop for (p . v) in params
                             append (list (intern (concat ":" p)) v))))
          (apply #'turpial-dsl-synth name flat-params)))
      (t (message "🚀 DSL: SynthDef '%s' compiled, added and registered." name)))))

(provide 'turpial-dsl)
;;; turpial-dsl.el ends here
