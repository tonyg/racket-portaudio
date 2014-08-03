#lang racket

(require "../main.rkt")

(define data (file->bytes "tmp-out.raw"))
(define offset 0)

(define s (pa-default-output-stream 2 'paInt16 48000 #f
				    (lambda (buffer flags current-time output-dac-time)
				      (define next-offset (min (bytes-length data) (+ offset (bytes-length buffer))))
				      (bytes-copy! buffer 0 data offset next-offset)
				      (set! offset next-offset)
				      (if (< offset (bytes-length data))
					  'paContinue
					  'paComplete))))
(pa-start-stream s)
(pa-wait-until-stream-inactive s)
(pa-close-stream s)
