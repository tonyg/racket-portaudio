#lang racket

(require "../main.rkt")

(define f (open-output-file "tmp-out.raw" #:exists 'replace))

(define start-time (current-inexact-milliseconds))
(define s (pa-default-input-stream 2
				   'paInt16
				   48000
				   #f
				   (lambda (bs flags current-time input-adc-time)
				     (write-bytes bs f)
				     (if (< (current-inexact-milliseconds) (+ start-time 3000))
					 'paContinue
					 'paComplete))))

(pa-start-stream s)
(pa-wait-until-stream-inactive s)
(pa-close-stream s)

(close-output-port f)
