#lang racket

(require "../main.rkt")

;; 48kHz sample rate, divided by 440Hz pitch, gives ~109 samples per cycle.
(define nsamples 109)
(define data (make-bytes (* nsamples 2 2))) ;; two bytes per sample, two channels

(for ((i nsamples))
  (define lo (if (< i (/ nsamples 2)) #x00 #xff))
  (define hi (if (< i (/ nsamples 2)) #x80 #x7f))
  (bytes-set! data (+ (* i 4) 0) lo)
  (bytes-set! data (+ (* i 4) 1) hi)
  (bytes-set! data (+ (* i 4) 2) lo)
  (bytes-set! data (+ (* i 4) 3) hi))

(define offset 0)

(define s (pa-default-output-stream 2 'paInt16 48000 #f
				    (lambda (buffer flags current-time output-dac-time)
				      (for ((i (bytes-length buffer)))
					(define j (remainder (+ i offset) (bytes-length data)))
					(bytes-set! buffer i (bytes-ref data j)))
				      (set! offset (+ offset (bytes-length buffer)))
				      'paContinue)))
(pa-start-stream s)
(pa-wait-until-stream-inactive s)
(pa-close-stream s)
