#lang racket/base

(require "../main.rkt")

(printf "This is PortAudio version ~a.\n" (pa-get-version))
(printf "  - text version: ~a\n" (pa-get-version-text))

(printf "API count: ~a\n" (pa-get-host-api-count))
(printf "Default API: ~a\n" (pa-get-default-host-api))
(pa-get-default-host-api-info)
(pa-get-last-host-error-info)

(printf "Device Count: ~a\n" (pa-get-device-count))
(printf "Default input device: ~a\n" (pa-get-default-input-device))
(printf "Default output device: ~a\n" (pa-get-default-output-device))
(pa-get-default-input-device-info)
(pa-get-default-output-device-info)

(printf "Stereo input/output on default devices as 16-bit ints at 48kHz supported? ~a\n"
	(pa-format-supported? (pa-stream-parameters (pa-get-default-input-device) 2 'paInt16 0.0)
			      (pa-stream-parameters (pa-get-default-output-device) 2 'paInt16 0.0)
			      48000))
