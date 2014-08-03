#lang racket

(require "../main.rkt")

(define data (file->bytes "tmp-out.raw"))

(define s (pa-default-output-stream 2 'paInt16 48000 #f #f))
(pa-start-stream s)
(pa-write-stream s data)
(pa-close-stream s)
