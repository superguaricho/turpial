;;; turpial-dsl-tests.el --- Tests for turpial-dsl  -*- lexical-binding: t; -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Filename: turpial-dsl-tests.el
;; Description: Tests for turpial-dsl
;; Author: Numa Tortolero
;; Version: 0.1.1
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; This file contains a series of tests and examples for the turpial-dsl
;; library, which provides a domain-specific language for defining and
;; controlling SuperCollider synths from Emacs Lisp. The tests cover basic
;; synth definitions, parameter control, sequencing, and routing. Each test
;; is designed to demonstrate a specific aspect of the DSL and how it interacts
;; with the SuperCollider server. To run the tests, ensure you have a SuperCollider
;; server running and that you have the turpial package properly set up in
;; your Emacs environment. You can execute each test block individually to hear
;; the results and see how the DSL constructs work in practice.
;;
;; You can see this file as a tutorial or a playground for experimenting with
;; the turpial-dsl features. Don't load it nor require it in your Emacs
;; configuration, just read the comments and evaluate the code blocks.
;; Enjoy it....
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
;;
;;; Code:

(progn
  (add-to-list  'load-path (file-name-directory (or load-file-name buffer-file-name)))

  (require 'turpial-dsl)
  (require 'turpial-scsynth)
  (require 'turpial-osc)
  )

(turpial-dsl-synthdef "elisp_fm_synth"
  :params '(("freq" . 440.0) ("m_ratio" . 2.0) ("m_index" . 100.0) ("amp" . 0.2))
  :nodes '((BinaryOpUGen :ar ("freq" "m_ratio") :special 2)  ;; UGen 1
            (SinOsc :ar (1 0.0))                             ;; UGen 2
            (BinaryOpUGen :ar (2 "m_index") :special 2)      ;; UGen 3
            (BinaryOpUGen :ar ("freq" 3) :special 0)         ;; UGen 4
            (SinOsc :ar (4 0.0))                             ;; UGen 5
            (BinaryOpUGen :ar (5 "amp") :special 2)          ;; UGen 6
            (Out :ar (0.0 6) :outputs 0)))                   ;; UGen 7

;; 2. DESPUÉS lo hacemos sonar (fuera de la definición)

(setq node 0)
(setq synth_1 5001)

(osc-send-message (turpial-osc-get-client)
  "/s_new" "elisp_fm_synth" synth_1 0 0
  "freq" 220.0)

;; silence
;; (osc-send-message (turpial-osc-get-client) "/n_free" synth_1)

;; (osc-send-message (turpial-osc-get-client) "/n_set" synth_1 "gate" 0.0)

;; (osc-send-message (turpial-osc-get-client) "/g_freeAll" 0)

(turpial-osc-panic)

(turpial-dsl-synthdef "sub_osc"
  :params '(("freq" . 55.0) ("amp" . 0.5))
  :nodes '((SinOsc :ar ("freq" 0.0))
            (BinaryOpUGen :ar (0 "amp") :special 2)
            (Out :ar (0.0 1) :outputs 0)))

(setq node_2 (turpial-dsl-synth "sub_osc" :freq 110 :amp 0.2))
(osc-send-message (turpial-osc-get-client) "/n_free" node_2)

(turpial-dsl-synthdef "flash_sine"
  :params '(("freq" . 880.0) ("amp" . 0.1))
  :action :play
  :nodes '((SinOsc :ar ("freq" 0.0))
            (BinaryOpUGen :ar (0 "amp") :special 2)
            (Out :ar (0.0 1) :outputs 0)))

(turpial-dsl-synthdef "elisp_fm_auto"
  :params '(("freq" . 440.0) ("m_ratio" . 2.0) ("m_index" . 100.0) ("amp" . 0.2) ("gate" . 1.0))
  :nodes '((BinaryOpUGen :ar ("freq" "m_ratio") :special 2 :as m_freq)
            (SinOsc :ar (m_freq 0.0) :as modulator)
            (BinaryOpUGen :ar (modulator "m_index") :special 2 :as deviation)
            (BinaryOpUGen :ar ("freq" deviation) :special 0 :as c_freq)
            (SinOsc :ar (c_freq 0.0) :as carrier)
            ;; Envolvente ASR (Attack-Sustain-Release)
            ;; Argumentos: gate, levelScale, levelBias, timeScale, doneAction, envelopeData...
            (EnvGen :kr ("gate" 1.0 0.0 1.0 2.0
                          0.0 2.0 1.0 -99.0 1.0 0.01 5.0 -4.0 0.0 0.1 5.0 -4.0) :as env)
            (BinaryOpUGen :ar (carrier env) :special 2 :as scaled)
            (BinaryOpUGen :ar (scaled "amp") :special 2 :as final_sig)
            (Out :ar (0.0 final_sig) :outputs 0)))

;; Y para tocarlo:
;; (turpial-dsl-synth "elisp_fm_auto" :freq 220 :m_index 500)

;; (turpial-osc-panic)

(turpial-dsl-synthdef "elisp_kick"
  :params '(("freq" . 60.0) ("amp" . 0.5) ("rel" . 0.3))
  :nodes `((EnvGen :kr (1.0 1.0 0.0 1.0 0.0 ,(turpial-dsl-env-perc 0.005 0.05))
             :as f_env)
            (BinaryOpUGen :kr (f_env "freq") :special 2 :as k_freq)
            (SinOsc :ar (k_freq 0.0) :as osc)
            (EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "rel"))
              :as a_env)
            (BinaryOpUGen :ar (osc a_env) :special 2 :as sig)
            (BinaryOpUGen :ar (sig "amp") :special 2 :as final)
            (Out :ar (0.0 final) :outputs 0))
  :action :add)

;; Tocarlo (puedes llamarlo varias veces para hacer un ritmo)
(turpial-dsl-synth "elisp_kick" :freq 60 :rel 0.1)
(turpial-dsl-synth "elisp_kick" :freq 45 :rel 0.5)

;; (turpial-osc-panic)

(turpial-dsl-synthdef "sine_decay"
  :params '(("freq" . 440.0) ("amp" . 0.5) ("dur" . 1.0))
  :nodes `((EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-line 1.0 0.0
                                               "dur")) :as amp_env)
            (SinOsc :ar ("freq" 0.0) :as sine)
            (BinaryOpUGen :ar (sine amp_env) :special 2 :as scaled_sine)
            (BinaryOpUGen :ar (scaled_sine "amp") :special 2 :as final)
            (Out :ar (0.0 final) :outputs 0))
  :action :add)

(defvar turpial-dsl-registry nil)

(add-to-list 'turpial-dsl-registry "sine_decay")

(d1 "sine_decay*4" :freq 220)

(hush)

;; Pruébalo con un segundo de duración
(turpial-dsl-synth "sine_decay" :freq 660 :dur 3.0 :amp 0.4)

(turpial-dsl-synth "sine_decay" :freq 580 :dur 3.0 :amp 0.3)
(turpial-dsl-synth "sine_decay" :freq 440 :dur 3.0 :amp 0.3)

;; O algo más largo
(turpial-dsl-synth "sine_decay" :freq 330 :dur 3.0 :amp 0.3)

(hush)

;;  Detalles técnicos del cambio:
;;   * Segmentos: Una línea es simplemente una envolvente con 1 segmento.
;;   * Shape 1.0: En el protocolo de SuperCollider, el valor 1.0 en el campo de "forma"
;; del segmento indica una transición lineal.
;;   * doneAction 2.0: Al igual que antes, el 2.0 le dice al servidor que libere el
;; sintetizador automáticamente cuando la línea llegue a su destino.

(turpial-dsl-synthdef "elisp_noise_party"
  :params '(("freq" . 220.0) ("amp" . 0.2) ("dur" . 2.0))
  :nodes `(;; Envolvente principal
            (EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-line 1.0 0.0
                                                "dur")) :as env)
            ;; Ruido Blanco (WhiteNoise) - no tiene argumentos
            (WhiteNoise :ar () :as noise)
            ;; Pulso con ancho variable (LFPulse: freq, phase, width)
            (LFPulse :ar ("freq" 0.0 0.1) :as pulse)
            ;; Sierra (LFSaw: freq, phase)
            (LFSaw :ar ("freq" 0.0) :as saw)
            ;; Mezclamos (Saw + Pulse + Noise*0.2)
            (BinaryOpUGen :ar (saw pulse) :special 0 :as mix1) ;; saw + pulse
            (BinaryOpUGen :ar (noise 0.2) :special 2 :as soft_noise)
            (BinaryOpUGen :ar (mix1 soft_noise) :special 0 :as mix2) ;; mix1 + soft_noise
            ;; Aplicamos envolvente y amplitud
            (BinaryOpUGen :ar (mix2 env) :special 2 :as sig)
            (BinaryOpUGen :ar (sig "amp") :special 2 :as final)
            (Out :ar (0.0 final) :outputs 0))
  :action :add)

;; (turpial-dsl-synth "elisp_noise_party" :freq 220 :dur 3.0 :amp 0.3)

(turpial-dsl-synthdef "filtered_noise"
  :params '(("cutoff" . 1000.0) ("amp" . 0.5))
  :nodes `((WhiteNoise :ar () :as noise)
            ;; LPF: input, frequency
            (LPF :ar (noise "cutoff") :as filtered)
            (Out :ar (0.0 filtered) :outputs 0))
  :action :play)

;; Cambia el filtro en tiempo real si quieres:
;; (osc-send-message (turpial-osc-get-client) "/n_set" <node-id> "cutoff" 500.0)

(turpial-dsl-synthdef "elisp_acid_303"
  :params '(("freq" . 55.0)      ;; Nota base (grave)
             ("res" . 0.5)       ;; Resonancia (0.0 a 1.0)
             ("cutoff" . 1000.0) ;; Frecuencia base del filtro
             ("env_amt" . 2000.0);; Cuánto afecta la envolvente al filtro
             ("dur" . 0.5)       ;; Duración de la nota
             ("amp" . 0.3))
  :nodes `(;; 1. Envolventes (Amplitud y Filtro)
            ;; Envolvente de Filtro: cae rápido para el ataque
            (EnvGen :kr (1.0 1.0 0.0 1.0 0.0 ,(turpial-dsl-env-perc 0.01 "dur"))
              :as f_env)
            ;; Envolvente de Amplitud
            (EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "dur"))
              :as a_env)

            ;; 2. El Oscilador (Onda de Sierra)
            (LFSaw :ar ("freq" 0.0) :as saw)

            ;; 3. Preparación del Filtro
            ;; Calculamos la frecuencia del filtro: base + (env * amt)
            (BinaryOpUGen :kr (f_env "env_amt") :special 2 :as f_mod)
            (BinaryOpUGen :kr ("cutoff" f_mod) :special 0 :as f_final)

            ;; 4. El Filtro Resonante (RLPF: input, freq, rq)
            ;; RQ es 1/Q (resonancia inversa). 0.1 es muy resonante, 1.0 es poco.
            ;; Mapeamos nuestro parámetro 'res' de 0-1 a un RQ de 1.0-0.1
            (BinaryOpUGen :kr ("res" -0.9) :special 2 :as r_inv)
            (BinaryOpUGen :kr (1.0 r_inv) :special 0 :as rq)
            (RLPF :ar (saw f_final rq) :as filtered)

            ;; 5. Salida Final con Amplitud
            (BinaryOpUGen :ar (filtered a_env) :special 2 :as sig)
            (BinaryOpUGen :ar (sig "amp") :special 2 :as final)
            (Out :ar (0.0 final) :outputs 0))
  :action :add)

;; Tocarlo con resonancia baja
;; (turpial-dsl-synth "elisp_acid_303" :freq 55 :res 0.2 :cutoff 800 :dur 0.5)

;; Tocarlo con resonancia alta (el clásico sonido ACID)
;; (turpial-dsl-synth "elisp_acid_303" :freq 55 :res 0.8 :cutoff 400 :env_amt 3000  :dur 0.3)

(turpial-dsl-synthdef "elisp_acid_303"
  :params '(("freq" . 55.0)      ;; Nota base (grave)
             ("res" . 0.5)       ;; Resonancia (0.0 a 1.0)
             ("cutoff" . 1000.0) ;; Frecuencia base del filtro
             ("env_amt" . 2000.0);; Cuánto afecta la envolvente al filtro
             ("dur" . 0.5)       ;; Duración de la nota
             ("amp" . 0.3))
  :nodes `(;; 1. Envolventes (Amplitud y Filtro)
            ;; Envolvente de Filtro: cae rápido para el ataque
            (EnvGen :kr (1.0 1.0 0.0 1.0 0.0 ,(turpial-dsl-env-perc 0.01 "dur"))
              :as f_env)
            ;; Envolvente de Amplitud
            (EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "dur"))
              :as a_env)

            ;; 2. El Oscilador (Onda de Sierra)
            (LFSaw :ar ("freq" 0.0) :as saw)

            ;; 3. Preparación del Filtro
            ;; Calculamos la frecuencia del filtro: base + (env * amt)
            (BinaryOpUGen :kr (f_env "env_amt") :special 2 :as f_mod)
            (BinaryOpUGen :kr ("cutoff" f_mod) :special 0 :as f_final)

            ;; 4. El Filtro Resonante (RLPF: input, freq, rq)
            ;; RQ es 1/Q (resonancia inversa). 0.1 es muy resonante, 1.0 es poco.
            ;; Mapeamos nuestro parámetro 'res' de 0-1 a un RQ de 1.0-0.1
            (BinaryOpUGen :kr ("res" -0.9) :special 2 :as r_inv)
            (BinaryOpUGen :kr (1.0 r_inv) :special 0 :as rq)
            (RLPF :ar (saw f_final rq) :as filtered)

            ;; 5. Salida Final con Amplitud
            (BinaryOpUGen :ar (filtered a_env) :special 2 :as sig)
            (BinaryOpUGen :ar (sig "amp") :special 2 :as final)
            (Out :ar (0.0 final) :outputs 0))
  :action :add)

;; Tocarlo con resonancia baja
;; (turpial-dsl-synth "elisp_acid_303" :freq 55 :res 0.2 :cutoff 800 :dur 0.5)

;; Tocarlo con resonancia alta (el clásico sonido ACID)
;; (turpial-dsl-synth "elisp_acid_303" :freq 55 :res 0.8 :cutoff 400 :env_amt 3000 :dur 0.3)

(hush)

(require 'turpial-seq)

;; Definimos una secuencia de bajo (una lista de propiedades)
(defvar my-acid-line
  '((:freq 55    :dur 0.25 :res 0.8 :cutoff 400 :env_amt 3000)
     (:freq 55   :dur 0.25 :res 0.2 :cutoff 800)
     (:freq 65.4 :dur 0.25 :res 0.9 :cutoff 300 :env_amt 5000)
     (:freq 55   :dur 0.25 :res 0.4 :cutoff 1200)
     (:freq 82.4 :dur 0.5  :res 0.7 :cutoff 500 :env_amt 2000)
     (:freq 73.4 :dur 0.25 :res 0.5 :cutoff 900)))

;; ¡A tocar!
;; (turpial-seq-play "elisp_acid_303" my-acid-line)

;; (turpial-seq-stop)
;; (turpial-osc-panic)

;; A. Definimos el Synth de Reverb (el efecto)
(turpial-dsl-synthdef "fx_reverb"
  :params '(("in_bus" . 16.0) ("mix" . 0.5) ("room" . 0.8) ("damp" . 0.5))
  :nodes '((In :ar ("in_bus" 2) :as input) ;; Lee 2 canales del bus 16
            (FreeVerb :ar (input "mix" "room" "damp") :as reverb)
            (Out :ar (0.0 reverb) :outputs 0)))

(turpial-dsl-synthdef "fx_reverb_v2"
  :params '(("in_bus" . 16.0) ("mix" . 0.33) ("room" . 0.5) ("damp" . 0.5))
  :nodes '((In :ar ("in_bus" 1) :as input) ;; Aseguramos entrada MONO
            (FreeVerb :ar (input "mix" "room" "damp") :as reverb)
            ;; Duplicamos la señal reverb para salir en estéreo (canal 0 y 1)
            (Out :ar (0.0 reverb reverb) :outputs 0)))

(turpial-dsl-synthdef "fx_reverb_v4"
  :params '(("in_bus" . 16.0) ("mix" . 0.33) ("room" . 0.5) ("damp" . 0.5))
  :nodes '((In :ar ("in_bus") :outputs 2 :as input) ;; 1 entrada, 2 salidas
            ;; FreeVerb2 recibe las dos salidas de In, mix, room y damp
            (FreeVerb2 :ar ((input 0) (input 1) "mix" "room" "damp") :outputs 2 :as
              reverb)
            ;; Out recibe el bus de salida (0.0) y las dos salidas de la reverb
            (Out :ar (0.0 (reverb 0) (reverb 1)) :outputs 0)))

;; Para probar (recuerda lanzarlo después de los sintetizadores o usar addAction 1)
;; (turpial-dsl-synth "fx_reverb_v4" :in_bus 16.0 :addAction 1 :target 1)

;; B. Definimos un sonido que manda su salida al bus 16
(turpial-dsl-synthdef "acid_to_fx"
  :params '(("freq" . 55.0) ("out_bus" . 16.0) ("dur" . 0.5))
  :nodes `((EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "dur"))
             :as env)
            (LFSaw :ar ("freq" 0.0) :as saw)
            (BinaryOpUGen :ar (saw env) :special 2 :as sig)
            (Out :ar ("out_bus" sig) :outputs 0)))

;; C. CÓMO USARLO:
;; 1. Primero lanzamos el efecto (Node 1) al final del grupo 1
(setq reverb-node (turpial-dsl-synth "fx_reverb_v4" :in_bus 16.0 :addAction 1 :target 1))

;; 2. Luego lanzamos el sonido (irá antes del efecto)
;; (turpial-dsl-synth "acid_to_fx" :freq 110 :out_bus 16.0)

;; (turpial-osc-record-start "~/mi_obra_maestra.wav")

;; (turpial-seq-play "elisp_acid_303" my-acid-line)

;;;

(turpial-dsl-synthdef "acid_source"
  :params '(("freq" . 110.0) ("out_bus" . 20.0) ("amp" . 0.5) ("dur" . 0.5))
  :nodes `((EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "dur"))
             :as env)
            (LFSaw :ar ("freq" 0.0) :as saw)
            (BinaryOpUGen :ar (saw env) :special 2 :as sig)
            (BinaryOpUGen :ar (sig "amp") :special 2 :as final)
            ;; Mandamos 'final' a dos canales (estéreo) empezando en out_bus
            (Out :ar ("out_bus" final final) :outputs 0))
  :action :add)

(turpial-dsl-synthdef "fx_monitor"
  :params '(("in_bus" . 20.0))
  :nodes '((In :ar ("in_bus") :outputs 2 :as input)
            (Out :ar (0.0 (input 0) (input 1)) :outputs 0))
  :action :add)

;; Prueba el monitor:
;; (turpial-dsl-synth "fx_monitor" :in_bus 20.0 :addAction 1 :target 1)
;; (turpial-dsl-synth "acid_source" :freq 220 :out_bus 20.0)


(turpial-dsl-synthdef "debug_sine"
  :params '(("freq" . 440.0) ("amp" . 0.2))
  :nodes '((SinOsc :ar ("freq" 0.0) :as s)
            (BinaryOpUGen :ar (s "amp") :special 2 :as scaled)
            ;; Salida directa a los altavoces (Bus 0.0)
            ;; Ponemos 'scaled' dos veces para estéreo
            (Out :ar (0.0 scaled scaled) :outputs 0))
  :action :add)

;; (turpial-dsl-synth "debug_sine" :freq 440 :amp 0.3)


;; A. Definir el origen (manda al bus 4.0)
(turpial-dsl-synthdef "routing_test_source"
  :params '(("out_bus" . 4.0) ("freq" . 220.0))
  :nodes '((SinOsc :ar ("freq" 0.0) :as s)
            (Out :ar ("out_bus" s) :outputs 0))
  :action :add)

;; B. Definir el puente (lee del bus 4.0 y lo saca por el 0.0)
(turpial-dsl-synthdef "routing_test_bridge"
  :params '(("in_bus" . 4.0))
  :nodes '((In :ar ("in_bus") :outputs 1 :as input)
            (Out :ar (0.0 input input) :outputs 0))
  :action :add)

;; --- PRUEBA ---
;; 1. Primero lanzamos el puente al final (tail)
;; (turpial-dsl-synth "routing_test_bridge" :in_bus 4.0 :addAction 1 :target 0)

;; 2. Luego lanzamos el sonido
;; (turpial-dsl-synth "routing_test_source" :freq 440 :out_bus 4.0)

;;;

;; 1. Definimos la Fuente (Source)
(turpial-dsl-synthdef "routing_src"
  :params '(("out_bus" . 100.0) ("freq" . 440.0))
  :nodes '((SinOsc :ar ("freq" 0.0) :as s)
            (Out :ar ("out_bus" s) :outputs 0)))

;; 2. Definir el Puente (Bridge)
(turpial-dsl-synthdef "routing_brg"
  :params '(("in_bus" . 100.0))
  :nodes '((In :ar ("in_bus") :outputs 1 :as input)
            (Out :ar (0.0 input input) :outputs 0)))

;; --- FLUJO DE EJECUCIÓN (El orden importa aquí) ---

;; PASO A: Lanzamos el PUENTE al FINAL (tail) del grupo por defecto (1)
;; Esto asegura que el puente se quede esperando al final de la cadena.
;; (turpial-dsl-synth "routing_brg" :in_bus 100.0 :addAction 1 :target 1)

;; PASO B: Lanzamos la FUENTE al PRINCIPIO (head) del grupo (1)
;; Al usar :addAction 0, forzamos a que este sintetizador se ejecute ANTES que el puente.
;; (turpial-dsl-synth "routing_src" :freq 220.0 :out_bus 100.0 :addAction 0 :target 1)

;; A. Definimos la Reverb (V5) - Optimizada
(turpial-dsl-synthdef "fx_reverb_v5"
  :params '(("in_bus" . 100.0) ("mix" . 0.5) ("room" . 0.9) ("damp" . 0.5))
  :nodes '((In :ar ("in_bus") :outputs 1 :as input)
            (FreeVerb :ar (input "mix" "room" "damp") :as reverb)
            (Out :ar (0.0 reverb reverb) :outputs 0)))

;; B. El Bajo Acid mandando al bus 100
(turpial-dsl-synthdef "acid_reverb_src"
  :params '(("freq" . 55.0) ("out_bus" . 100.0) ("res" . 0.8) ("cutoff" . 800.0)
             ("dur" . 0.5))
  :nodes `((EnvGen :kr (1.0 1.0 0.0 1.0 2.0 ,(turpial-dsl-env-perc 0.01 "dur"))
             :as env)
            (LFSaw :ar ("freq" 0.0) :as saw)
            (BinaryOpUGen :kr (env 1000.0) :special 2 :as f_mod)
            (BinaryOpUGen :kr ("cutoff" f_mod) :special 0 :as f_final)
            (RLPF :ar (saw f_final 0.2) :as filtered)
            (BinaryOpUGen :ar (filtered env) :special 2 :as sig)
            (Out :ar ("out_bus" sig) :outputs 0)))

;; --- FLUJO DE EJECUCIÓN ---
;; 1. Primero el efecto al FINAL (tail)
(turpial-dsl-synth "fx_reverb_v5" :in_bus 100.0 :room 0.95 :addAction 1 :target 0)

;; 2. Luego el bajo al PRINCIPIO (head)
(turpial-dsl-synth "acid_reverb_src" :freq 55 :out_bus 100.0 :res 0.8 :dur 1.0 :addAction 0 :target 0)

;;;

(turpial-dsl-synthdef "elisp_grain_noise"
  :params '(("freq" . 20.0)  ;; Frecuencia de disparo de granos (Hz)
             ("dur" . 0.1)       ;; Duración de cada grano (seg)
             ("amp" . 0.3)
             ("out_bus" . 100.0))
  :nodes `(;; 1. Impulso para disparar granos (Dust: density)
            (Dust :ar ("freq") :as trigger)

            ;; 2. Generador de Ruido Rosa (fuente de los granos)
            (PinkNoise :ar () :as source)

            ;; 3. Envolvente por grano (usamos un oscilador de pulso
            ;;    como gate simplificado para este experimento)
            (LFPulse :ar ("freq" 0.0 "dur") :as env)

            ;; 4. Multiplicamos la fuente por la envolvente
            (BinaryOpUGen :ar (source env) :special 2 :as grains)

            ;; 5. Salida final
            (BinaryOpUGen :ar (grains "amp") :special 2 :as final)
            (Out :ar ("out_bus" final final) :outputs 0)))

;; 1. Lanzamos la Reverb al FINAL (tail)
(turpial-dsl-synth "fx_reverb_v5"
  :in_bus 100.0
  :room 0.98
  :mix 0.8
  :addAction 1
  :target 0)

;; 2. Lanzamos la nube granular al PRINCIPIO (head)
(turpial-dsl-synth "elisp_grain_noise"
  :freq 50
  :dur 0.02
  :out_bus 100.0
  :amp 1.2
  :addAction 0
  :target 0)

;; ¿Cómo interactuar con la nube?
;; Mientras el granular suena, puedes cambiar su densidad (frecuencia de granos) o su
;; duración en tiempo real usando /n_set o enviando un nuevo Synth. Pero lo más divertido
;; es:
;; Aumenta la densidad (más granos por segundo)
;; (osc-send-message (turpial-osc-get-client) "/n_set" 0 "freq" 800.0)

;; Reduce la duración de los granos para que suene como "arena"
;; (osc-send-message (turpial-osc-get-client) "/n_set" 0 "amp" 2.0)

;;

(turpial-dsl-synth "fx_reverb_v5" :in_bus 100.0 :room 0.95 :addAction 1 :target 0)

;; 2. Luego el granular o el bajo (en el head)
(turpial-dsl-synth "elisp_grain_noise" :freq 40 :dur 0.05 :out_bus 100.0 :addAction 0 :target 0)

;;;

(turpial-dsl-synthdef "elisp_grain_organic"
  :params '(("dens" . 20.0)      ;; Granos por segundo
             ("freq" . 1000.0)    ;; Tono del grano
             ("dec" . 0.05)       ;; Caída del grano (decay)
             ("amp" . 0.2)
             ("out_bus" . 100.0))
  :nodes `(;; 1. Triggers aleatorios
            (Dust :ar ("dens") :as trigger)
            ;; 2. Filtro que resuena con cada trigger (Ringz: in, freq, decaytime)
            (Ringz :ar (trigger "freq" "dec") :as grains)
            ;; 3. Limitamos un poco la amplitud porque Ringz puede ser fuerte
            (BinaryOpUGen :ar (grains "amp") :special 2 :as final)
            (Out :ar ("out_bus" final final) :outputs 0)))

;; Lanzar con Reverb para un sonido etéreo
(turpial-dsl-synth "fx_reverb_v5" :in_bus 100.0 :room 0.9 :mix 0.5 :addAction 1 :target 0)
(turpial-dsl-synth "elisp_grain_organic" :dens 40 :freq 1200 :dec 0.02 :out_bus 100.0 :addAction 0 :target 0)

;;;

;; 1. Cargamos el archivo en el Buffer 0
(turpial-osc-buffer-alloc-read "/usr/share/sounds/alsa/Front_Center.wav" 0)

;; 2. Definimos el Granulador de Buffer
(turpial-dsl-synthdef "elisp_buffer_granular"
  :params '(("dens" . 20.0) ("buf" . 0.0) ("pos" . 0.5) ("dur" . 0.1) ("amp" .
                                                                        0.4))
  :nodes '((Dust :ar ("dens") :as trigger)
            ;; TGrains en el servidor recibe:
            ;; trigger, bufnum, rate, centerPos, dur, pan, amp, interp
            (TGrains :ar (trigger "buf" 1.0 "pos" "dur" 0.0 "amp" 2.0)
              :outputs 2
              :as grains)
            (Out :ar (0.0 (grains 0) (grains 1)) :outputs 0)))

;; 3. A jugar con el sonido
(turpial-dsl-synth "elisp_buffer_granular" :dens 50 :buf 0.0 :pos 0.3 :dur 0.05 :amp 1.8)

;; ¿Qué hace TGrains?
;; Este es el UGen "Dios" del granular en SuperCollider. Él mismo se encarga de:
;; * Crear los granos con ventanas suaves (adiós a los glitches).
;; * Gestionar la posición dentro del archivo de audio (pos).
;; * Permitir que los granos se solapen de forma fluida.

;; Para detenerlo:
(turpial-seq-stop)

(turpial-osc-panic)

(provide 'turpial-dsl-tests)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; turpial-dsl-tests.el ends here
