;;; turpial-osc.el --- OSC communication for SuperCollider in Emacs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Author: Numa Tortolero
;; Version: 0.1.1
;; Keywords: SuperCollider, OSC, Audio
;; URL: https://github.com/superguaricho/turpial
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;; This file provides functions to communicate with SuperCollider's
;; synthesis server (scsynth) directly via OSC from Emacs Lisp.
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

(require 'osc)
(require 'sclang)

(defgroup turpial-osc nil
  "OSC communication for SuperCollider."
  :group 'turpial)

(defcustom turpial-osc-scsynth-port 57110
  "Default port for SuperCollider's scsynth server."
  :type 'integer
  :group 'turpial-osc)

(defcustom turpial-osc-scsynth-host "127.0.0.1"
  "Default host for SuperCollider's scsynth server."
  :type 'string
  :group 'turpial-osc)

(defvar turpial-osc--client nil
  "Internal OSC client process for scsynth.")

(defun turpial-osc--default-handler (path &rest args)
  "Log unknown OSC messages to the monitor."
  (when (fboundp 'turpial-scsynth--log)
    (turpial-scsynth--log (format "<- %s %S" path args) 'turpial-scsynth-in-face)))

(defun turpial-osc-get-client ()
  "Get or create the OSC client for scsynth.
Ensures it is bidirectional to receive replies."
  (unless (and turpial-osc--client
            (process-live-p turpial-osc--client))
    (setq turpial-osc--client
      (osc-make-client turpial-osc-scsynth-host
        turpial-osc-scsynth-port)))
  ;; Always ensure the filter and generic handler are active
  (when (and turpial-osc--client (process-live-p turpial-osc--client))
    (set-process-filter turpial-osc--client 'osc-filter)
    ;; Use process-put for reliability (it updates the internal plist correctly)
    (process-put turpial-osc--client :generic #'turpial-osc--default-handler)
    (unless (process-get turpial-osc--client :handlers)
      (process-put turpial-osc--client :handlers nil)))
  turpial-osc--client)

(defun turpial-osc-get-server ()
  "Get or create the OSC server for receiving replies.
By default listens on 127.0.0.1:57130 (avoiding sclang 57120)."
  (unless (and turpial-osc--server
            (process-live-p turpial-osc--server))
    ;; Use our default handler instead of nil to avoid "void: nil" errors
    (setq turpial-osc--server
      (osc-make-server "127.0.0.1" 57130 #'turpial-osc--default-handler)))
  turpial-osc--server)

(defun turpial-osc-stop-client ()
  "Stop and clear the internal OSC client."
  (interactive)
  (when (and turpial-osc--client (process-live-p turpial-osc--client))
    (delete-process turpial-osc--client)
    (setq turpial-osc--client nil)
    (message "🔇 OSC Client stopped.")))

(defvar turpial-osc--server nil
  "Internal OSC server to receive replies from scsynth.")

;;;###autoload
(defun turpial-osc-play-default (&optional freq)
  "Produce a 3-second sound using SuperCollider's default oscillator.
FREQ defaults to 440Hz if not specified."
  (interactive "P")
  (let* ((client (turpial-osc-get-client))
          (node-id 1001) ; Unique ID for this synth node
          (frequency (or freq 440)))

    ;; Send /s_new message: [synthName, nodeID, addAction, targetID, args...]
    ;; addAction 1 = add to head of group
    ;; targetID 1 = default group
    (osc-send-message client "/s_new" "default" node-id 1 1
      "freq" (float frequency)
      "amp" 0.2
      "gate" 1)

    (message "🔊 Playing default synth at %dHz for 3 seconds..." frequency)

    ;; Schedule the release after 3 seconds
    (run-at-time 3 nil
      (lambda (c nid)
        (osc-send-message c "/n_set" nid "gate" 0)
        (message "🔇 Synth released."))
      client node-id)))

;;;###autoload
(defun turpial-osc-define-simple-synth ()
  "Define a simple sine synth in SuperCollider from Emacs."
  (interactive)
  (sclang-eval-string
    "(
    SynthDef(\"emacs_sine\", { |out=0, freq=440, amp=0.2, gate=1|
        var env = EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: 2);
        var sig = SinOsc.ar(freq) * env * amp;
        Out.ar(out, sig ! 2);
    }).add;
    \"🎹 [Emacs] SynthDef 'emacs_sine' has been added to the server.\".postln;
    )")
  (message "🎹 Sending SynthDef 'emacs_sine' to SuperCollider..."))

;;;###autoload
(defun turpial-osc-play-simple-synth (&optional freq)
  "Play the custom \\emacs_sine synth for 3 seconds."
  (interactive "P")
  (let* ((client (turpial-osc-get-client))
          (node-id 2001)
          (frequency (or freq 440)))

    ;; Create the synth
    (osc-send-message client "/s_new" "emacs_sine" node-id 1 1
      "freq" (float frequency)
      "amp" 0.3
      "gate" 1)

    (message "🎶 Playing \\emacs_sine at %dHz..." frequency)

    ;; Release after 3 seconds
    (run-at-time 3 nil
      (lambda (c nid)
        (osc-send-message c "/n_set" nid "gate" 0)
        (message "🔇 \\emacs_sine released."))
      client node-id)))

(defun turpial-osc-panic ()
  "Stop all sounds, free all nodes, and stop all sequences."
  (interactive)
  (let ((client (turpial-osc-get-client)))
    ;; 1. Stop Elisp-side sequencer if it exists
    (when (fboundp 'turpial-seq-stop)
      (turpial-seq-stop))

    ;; 2. Stop any Tidal-like patterns if they exist
    (when (fboundp 'hush)
      (hush))

    ;; 3. Free ALL nodes on the server (starting from root node 0)
    (osc-send-message client "/g_freeAll" 0)

    ;; 4. Clear server-side scheduler
    (osc-send-message client "/clearSched")

    ;; 5. Recreate default group (1) and any other essential SuperDirt groups
    ;; Recreating group 1 under the root node 0
    (osc-send-message client "/g_new" 1 0 0)

    (message "🔇 TOTAL PANIC: Server cleaned and reset (Group 1 restored).")))

(provide 'turpial-osc)
;;; turpial-osc.el ends here
