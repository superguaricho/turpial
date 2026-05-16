;;; turpial-scsynth.el --- OSC Monitor and scsynth control -*- lexical-binding: t; -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Author: Numa Tortolero
;; Version: 0.1.1
;; URL: https://github.com/superguaricho/turpial
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; OCS Monitor and scsynth control from Emacs.
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
(require 'cl-lib)
(require 'turpial-osc)

(defgroup turpial-scsynth nil
  "Monitor and control for SuperCollider's scsynth."
  :group 'turpial)

(defcustom turpial-scsynth-program "scsynth"
  "Path to the scsynth executable."
  :type 'string
  :group 'turpial-scsynth)

(defcustom turpial-scsynth-args '("-u" "57110")
  "Arguments passed to scsynth on boot."
  :type '(list string)
  :group 'turpial-scsynth)

(defvar turpial-scsynth--process nil "The active scsynth process started by Emacs.")
(defvar turpial-scsynth-buffer-name "*scsynth-monitor*" "Name of the monitor buffer.")

(defvar turpial-scsynth--boot-timer nil "Timer for OSC polling during boot.")
(defvar turpial-scsynth--boot-attempts 0 "Counter for boot polling attempts.")

;; --- Faces ---
(defface turpial-scsynth-out-face '((t :foreground "cyan" :weight bold)) "Outgoing OSC.")
(defface turpial-scsynth-in-face '((t :foreground "white")) "Internal SC output.")
(defface turpial-scsynth-err-face '((t :foreground "orange" :slant italic)) "Late/Error messages.")
(defface turpial-scsynth-info-face '((t :foreground "blue" :weight bold)) "Monitor info.")

;; --- Mode & Keymap ---

(defvar turpial-scsynth-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'turpial-scsynth-monitor-clear)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `turpial-scsynth-mode'.")

(define-derived-mode turpial-scsynth-mode special-mode "scsynth-monitor"
  "Major mode for monitoring OSC traffic."
  (setq-local buffer-read-only t))

;; --- Core Functions ---

(defun turpial-scsynth--log (text &optional face)
  "Internal: Log TEXT to the monitor buffer with FACE and force scroll."
  (let ((buf (get-buffer-create turpial-scsynth-buffer-name)))
    (with-current-buffer buf
      (unless (eq major-mode 'turpial-scsynth-mode)
        (turpial-scsynth-mode))
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (point-max))
          (let ((timestamp (format-time-string "[%H:%M:%S] ")))
            (insert (propertize timestamp 'face 'turpial-scsynth-info-face))
            (insert (if face (propertize text 'face face) text))
            (unless (string-suffix-p "\n" text) (insert "\n"))))
        ;; Force scroll to end in all windows showing this buffer
        (dolist (win (get-buffer-window-list buf nil t))
          (set-window-point win (point-max)))))))

(defun turpial-scsynth-monitor-clear ()
  "Clear the contents of the scsynth monitor buffer."
  (interactive)
  (let ((buf (get-buffer turpial-scsynth-buffer-name)))
    (when buf
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (propertize "--- Monitor Cleared ---\n" 'face 'turpial-scsynth-info-face))))
      (message "✨ Monitor cleared."))))

(defun turpial-scsynth-filter (proc string)
  "Filter for the scsynth process output."
  (let ((face (if (string-match-p "late\\|error\\|fail" string)
                'turpial-scsynth-err-face
                'turpial-scsynth-in-face)))
    (turpial-scsynth--log string face)))

(defun turpial-scsynth-sentinel (proc event)
  "Sentinel for scsynth process."
  (turpial-scsynth--log (format "--- Process: %s ---" (string-trim event)) 'turpial-scsynth-info-face)
  (when (string-match-p "finished\\|exited\\|killed" event)
    (setq turpial-scsynth--process nil)
    (run-at-time 3 nil #'turpial-scsynth-monitor-close)))

;; --- Boot & Polling Logic ---

(defun turpial-scsynth--on-boot-ready (&rest args)
  "Callback called when scsynth responds to /status."
  (turpial-scsynth--log (format "<- %s %S" "/status.reply" args) 'turpial-scsynth-in-face)
  (when turpial-scsynth--boot-timer
    (cancel-timer turpial-scsynth--boot-timer)
    (setq turpial-scsynth--boot-timer nil)
    (setq turpial-scsynth--boot-attempts 0)
    (message "✅ scsynth is ready (OSC confirmed). Connecting Jack...")
    (turpial-jack-connect)))

(defun turpial-scsynth--poll-status ()
  "Send a /status message to scsynth and handle timeout."
  (setq turpial-scsynth--boot-attempts (1+ turpial-scsynth--boot-attempts))
  (if (> turpial-scsynth--boot-attempts 20) ; 10 seconds timeout
    (progn
      (when turpial-scsynth--boot-timer
        (cancel-timer turpial-scsynth--boot-timer)
        (setq turpial-scsynth--boot-timer nil))
      (setq turpial-scsynth--boot-attempts 0)
      (message "⚠️ Boot timeout: No OSC response from scsynth. Check *scsynth-monitor*."))
    (let ((client (turpial-osc-get-client)))
      ;; Use turpial-scsynth-send to see the polling in the monitor
      (turpial-scsynth-send client "/status"))))

;;;###autoload
(defun turpial-scsynth-boot ()
  "Boot scsynth, open the monitor, and start OSC polling for Jack connection."
  (interactive)
  (unless (executable-find turpial-scsynth-program)
    (error "❌ Executable '%s' not found in PATH" turpial-scsynth-program))
  (if (process-live-p turpial-scsynth--process)
    (turpial-scsynth-monitor-open)
    (let ((buf (get-buffer-create turpial-scsynth-buffer-name))
           (client (turpial-osc-get-client)))
      (with-current-buffer buf (let ((inhibit-read-only t)) (erase-buffer)))

      ;; 1. IMPORTANT: Register the handler on the CLIENT process
      ;; because scsynth replies to the source port.
      (osc-server-set-handler client "/status.reply" #'turpial-scsynth--on-boot-ready)

      ;; 2. Start the process
      (setq turpial-scsynth--boot-attempts 0)
      (setq turpial-scsynth--process
        (make-process :name "scsynth"
          :buffer buf
          :command (cons turpial-scsynth-program turpial-scsynth-args)
          :filter #'turpial-scsynth-filter
          :sentinel #'turpial-scsynth-sentinel
          :stderr buf
          :noquery t))

      ;; 3. Start polling every 0.5 seconds
      (when turpial-scsynth--boot-timer (cancel-timer turpial-scsynth--boot-timer))
      (setq turpial-scsynth--boot-timer (run-at-time 0.5 0.5 #'turpial-scsynth--poll-status))

      (turpial-scsynth-monitor-open)
      (message "🚀 scsynth booting (waiting for OSC response)..."))))

(defalias 'scsynth #'turpial-scsynth-boot)
(defalias 'sc-boot #'turpial-scsynth-boot)

;;;###autoload
(defun turpial-scsynth-monitor-open ()
  "Just open the monitor buffer."
  (interactive)
  (let ((buf (get-buffer-create turpial-scsynth-buffer-name)))
    (display-buffer buf)
    (with-current-buffer buf
      (goto-char (point-max))))
  (message "📺 Monitor open."))

;;;###autoload
(defun turpial-scsynth-monitor-close ()
  "Close the scsynth monitor window."
  (interactive)
  (let ((buf (get-buffer turpial-scsynth-buffer-name)))
    (when buf
      (let ((win (get-buffer-window buf)))
        (when win
          (delete-window win)
          (message "📺 Monitor window closed."))))))

;;;###autoload
(defun turpial-scsynth-monitor-toggle ()
  "Toggle monitor window and ensure scsynth is running."
  (interactive)
  (let ((buf (get-buffer turpial-scsynth-buffer-name)))
    (if (and buf (get-buffer-window buf))
      (delete-window (get-buffer-window buf))
      ;; 1. Open monitor
      (turpial-scsynth-monitor-open)
      ;; 2. Ensure scsynth is running
      (unless (or (and (boundp 'sclang-server-process) (process-live-p sclang-server-process))
                (process-live-p turpial-scsynth--process))
        (message "Server not detected. Starting scsynth...")
        (turpial-scsynth-boot)))))

;;;###autoload
(defun turpial-scsynth-send (client path &rest args)
  "Send OSC and log it."
  (let ((log-str (format "-> %s %s" path (cl-loop for a in args concat (format "%S " a)))))
    (turpial-scsynth--log log-str 'turpial-scsynth-out-face))
  (apply #'osc-send-message client path args))

(defun turpial-scsynth-quit ()
  "Stop the internal scsynth process."
  (interactive)
  (when (process-live-p turpial-scsynth--process)
    (delete-process turpial-scsynth--process)
    (message "🛑 scsynth stopped.")))

;; --- Jack Management ---

(defun turpial-jack-connect ()
  "Connect jack to SuperCollider asynchronously."
  (interactive)
  (message "🔌 Connecting SuperCollider to Jack...")
  (start-process "jack-conn-1" nil "jack_connect" "SuperCollider:out_1" "system:playback_1")
  (start-process "jack-conn-2" nil "jack_connect" "SuperCollider:out_2" "system:playback_2"))

(defun turpial-jack-buffer-quit ()
  "Quit any old jack-connection buffers safely."
  (interactive)
  (let ((buf (get-buffer "*jack-connection*")))
    (when buf
      (let ((win (get-buffer-window buf)))
        (when win (delete-window win))
        (kill-buffer buf))))
  (message "🧹 Jack connections cleanup done."))

(defvar turpial-jack-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'turpial-jack-connect)
    (define-key map (kbd "q") #'turpial-jack-buffer-quit)
    map)
  "Keymap for Jack connection management.")

;; --- Keybindings ---

(defvar turpial-scsynth-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "b") #'turpial-scsynth-boot)
    (define-key map (kbd "q") #'turpial-scsynth-quit)
    (define-key map (kbd "o") #'turpial-scsynth-monitor-open)
    (define-key map (kbd "m") #'turpial-scsynth-monitor-toggle)
    (define-key map (kbd "k") #'turpial-scsynth-monitor-clear)
    map)
  "Keymap for scsynth server management.")

;; Bind to emacs-lisp-mode
(define-key emacs-lisp-mode-map (kbd "C-c s") turpial-scsynth-map)
(define-key emacs-lisp-mode-map (kbd "C-c k") turpial-jack-map)

;; Bindings for sclang-mode if available
(with-eval-after-load 'sclang
  (define-key sclang-mode-map (kbd "C-c M") #'turpial-scsynth-monitor-toggle)
  (define-key sclang-mode-map (kbd "C-c s") turpial-scsynth-map))

(provide 'turpial-scsynth)
;;; turpial-scsynth.el ends here
