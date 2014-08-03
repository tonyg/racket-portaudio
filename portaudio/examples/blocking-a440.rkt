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

(define s (pa-default-output-stream 2 'paInt16 48000 #f #f))
(pa-start-stream s)
(let loop ()
  (pa-write-stream s data)
  (loop))
