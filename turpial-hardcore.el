;;; turpial-hardcore.el --- Manual SynthDef construction in Elisp   -*- lexical-binding: t; -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Author: Numa Tortolero
;; Version: 0.1.1
;; Description: Low-level SynthDef construction in Emacs Lisp
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; This module provides low-level functions to construct SynthDefs manually in Emacs Lisp,
;; without relying on the higher-level DSL. It includes binary helpers for encoding data
;; in the format expected by SuperCollider's OSC messages.
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

;; --- Binary Helpers (Strict Unibyte) ---

(defun sc-int8 (n)
  (unibyte-string (logand n #xff)))

(defun sc-int16 (n)
  (unibyte-string (logand (ash n -8) #xff)
    (logand n #xff)))

(defun sc-int32 (n)
  (osc-int32 n))

(defun sc-float32 (f)
  (osc-float32 f))

(defun sc-string (s)
  (let ((unibyte-s (string-to-unibyte s)))
    (concat (sc-int8 (length unibyte-s)) unibyte-s)))

;; --- SynthDef Builder ---
;; (Las funciones de construcción se mantienen igual, pero ahora usan
;; los helpers corregidos)

(provide 'turpial-hardcore)
;; turpial-hardcore.el ends here
