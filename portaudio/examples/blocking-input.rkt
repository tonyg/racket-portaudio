#lang racket

(require "../main.rkt")

(define f (open-output-file "tmp-out.raw" #:exists 'replace))

(define start-time (current-inexact-milliseconds))
(define s (pa-default-input-stream 2 'paInt16 48000 #f #f))

(pa-start-stream s)

(let loop ()
  (when (< (current-inexact-milliseconds) (+ start-time 3000))
    (define-values (overflowed? bs) (pa-read-stream s 500))
    (write-bytes bs f)
    (loop)))

(pa-close-stream s)

(close-output-port f)
