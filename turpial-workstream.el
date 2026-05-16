;;; turpial-workstream.el --- Tutorial and Interactive Workstream for Turpial  -*- lexical-binding: t; -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Filename: turpial-workstream.el
;; Description: Interactive tutorial to learn Turpial by doing.
;; Author: Numa Tortolero
;; Version: 0.1.1
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; Welcome to the Turpial Tutorial!
;;
;; This file is designed as an interactive "workstream". To learn how to
;; use Turpial, simply read the comments and evaluate the code blocks
;; using `C-x C-e` (eval-last-sexp).
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

(require 'turpial)

;; ---------------------------------------------------------------------
;; STEP 1: Boot the Sound Engine
;; ---------------------------------------------------------------------
;; Evaluate this line to start scsynth and connect Jack automatically:

;; (scsynth)

;; ---------------------------------------------------------------------
;; STEP 2: Your First Synth - "acid_bass"
;; ---------------------------------------------------------------------
;; Notice the use of ` :nodes ` with a backquote (`). This allows us to
;; "inject" Lisp functions like `turpial-dsl-env-perc` into the definition.

(turpial-dsl-synthdef "acid_bass"
  :params '(("freq" . 55.0) ("res" . 0.5) ("cutoff" . 800.0) ("dur" . 0.5))
  :nodes `(;; 1. Envelopes
            (EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "dur")) :as amp_env)
            ;; 2. Oscillator (Sawtooth)
            (LFSaw :ar ("freq" 0.0) :as saw)
            ;; 3. Resonant Filter
            (RLPF :ar (saw "cutoff" "res") :as filtered)
            ;; 4. Output (Stereo)
            (BinaryOpUGen :ar (filtered amp_env) :special 2 :as final)
            (Out :ar (0.0 final final) :outputs 0))
  :action :add)

;; Test it with a pattern:
;; (d1 "acid_bass*4" :cutoff 1200 :res 0.4)
;; (d1 silence)

;; ---------------------------------------------------------------------
;; STEP 3: Continuous Sounds - "test_loud"
;; ---------------------------------------------------------------------
;; This synth uses a `Line` that doesn't die, useful for testing constant signals.

(turpial-dsl-synthdef "test_loud"
  :params '(("freq" . 880.0))
  :nodes '((SinOsc :ar ("freq" 0.0) :as osc)
            (Line :kr (1.0 1.0 1.0) :as env)
            (BinaryOpUGen :ar (osc env) :special 2 :as sig)
            (Out :ar (0 sig sig))))


;; ---------------------------------------------------------------------
;; STEP 4: Decay Envelopes - "sine_decay" & "sine_decay2"
;; ---------------------------------------------------------------------
;; Here we see how to use `turpial-dsl-env-line` for smooth volume fades.

(turpial-dsl-synthdef "sine_decay"
  :params '(("freq" . 440.0) ("amp" . 0.5) ("dur" . 1.0))
  :nodes `((EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-line 1.0 0.0 "dur")) :as amp_env)
            (SinOsc :ar ("freq" 0.0) :as sine)
            (BinaryOpUGen :ar (sine amp_env) :special 2 :as scaled_sine)
            (BinaryOpUGen :ar (scaled_sine "amp") :special 2 :as final)
            (Out :ar (0.0 final) :outputs 0))
  :action :add)

;; "sine_decay2" uses a simpler `Line` UGen for the same effect.
(turpial-dsl-synthdef "sine_decay2"
  :params '(("freq" . 440.0) ("amp" . 0.2) ("dur" . 0.5) ("out" . 0.0))
  :nodes '((SinOsc :ar ("freq") :as osc)
            (Line :kr (1.0 0.0 "dur") :as env)
            (BinaryOpUGen :ar (osc env) :special 2 :as sig)
            (Out :ar ("out" sig))))


;; ---------------------------------------------------------------------
;; STEP 5: Complex Synthesis - FM (Frequency Modulation)
;; ---------------------------------------------------------------------
;; "elisp_fm_auto" shows how oscillators can modulate each other.

(turpial-dsl-synthdef "elisp_fm_auto"
  :params '(("freq" . 440.0) ("m_ratio" . 2.0) ("m_index" . 100.0) ("amp" . 0.2) ("gate" . 1.0))
  :nodes '((BinaryOpUGen :ar ("freq" "m_ratio") :special 2 :as m_freq)
            (SinOsc :ar (m_freq 0.0) :as modulator)
            (BinaryOpUGen :ar (modulator "m_index") :special 2 :as deviation)
            (BinaryOpUGen :ar ("freq" deviation) :special 0 :as c_freq)
            (SinOsc :ar (c_freq 0.0) :as carrier)
            ;; ASR Envelope (Attack-Sustain-Release)
            (EnvGen :kr ("gate" 1.0 0.0 1.0 2.0 0.0 2.0 1.0 -99.0 1.0 0.01 5.0 -4.0 0.0 0.1 5.0 -4.0) :as env)
            (BinaryOpUGen :ar (carrier env) :special 2 :as scaled)
            (BinaryOpUGen :ar (scaled "amp") :special 2 :as final_sig)
            (Out :ar (0.0 final_sig) :outputs 0)))

;; Try FM textures:
;; (d2 "elisp_fm_auto(3,8)" :m_index 500)


;; ---------------------------------------------------------------------
;; STEP 6: Percussion - "elisp_kick"
;; ---------------------------------------------------------------------
;; We use a very fast frequency envelope (`f_env`) to create the "thump" of a kick drum.

(turpial-dsl-synthdef "elisp_kick"
  :params '(("freq" . 60.0) ("amp" . 0.5) ("rel" . 0.3))
  :nodes `((EnvGen :kr (1.0 1.0 0.0 1.0 0.0 ,(turpial-dsl-env-perc 0.005 0.05)) :as f_env)
            (BinaryOpUGen :kr (f_env "freq") :special 2 :as k_freq)
            (SinOsc :ar (k_freq 0.0) :as osc)
            (EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "rel")) :as a_env)
            (BinaryOpUGen :ar (osc a_env) :special 2 :as sig)
            (BinaryOpUGen :ar (sig "amp") :special 2 :as final)
            (Out :ar (0.0 final) :outputs 0))
  :action :add)

;; (d3 "elisp_kick*4" :rel 0.1)


;; ---------------------------------------------------------------------
;; STEP 7: Performance & Cleaning
;; ---------------------------------------------------------------------

;; Stop all patterns:
;; (hush)

;; Emergency stop (frees all nodes on the server):
;; (turpial-osc-panic)

;; Close everything:
;; (turpial-scsynth-quit)

(provide 'turpial-workstream)
;;; turpial-workstream.el ends here
