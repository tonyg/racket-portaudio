#lang racket
;; PortAudio experimentation

(require ffi/unsafe)
(require ffi/unsafe/define)
(require ffi/unsafe/cvector)

(define pa-lib (ffi-lib "libportaudio"))

(define-ffi-definer define-pa pa-lib #:default-make-fail make-not-available)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-pa Pa_GetVersion (_fun -> _int))
(define-pa Pa_GetVersionText (_fun -> _string))
(define-pa Pa_GetErrorText (_fun _int -> _string))

(define paNoError 0)

(define (pa-ok? error-code)
  (not (negative? error-code)))

(define (die-if-error function-name error-code)
  (if (pa-ok? error-code)
      error-code
      (error function-name "PortAudio error: ~a (code ~a)" (Pa_GetErrorText error-code) error-code)))

(define-pa Pa_Initialize (_fun -> _void))
(define-pa Pa_Terminate (_fun -> _void))

(define paNoDevice -1)
(define paUseHostApiSpecificDeviceSpecification -2)

(define-pa Pa_GetHostApiCount (_fun -> _int))
(define-pa Pa_GetDefaultHostApi (_fun -> _int))
(define-pa Pa_GetHostApiInfo (_fun _int -> _pointer))

(struct pa-host-api-info (type-id name device-count default-input-device default-output-device) #:prefab)

(define (pa-get-host-api-info index)
  (define p (Pa_GetHostApiInfo index))
  (and p
       (match (ptr-ref p (_list-struct _int _int _string _int _int _int))
	 [(list 1 type-id name device-count default-input-device default-output-device)
	  (pa-host-api-info type-id name device-count default-input-device default-output-device)])))

(define-pa Pa_GetLastHostErrorInfo (_fun -> _pointer))

(struct pa-host-error-info (api-type error-code error-text) #:prefab)

(define (pa-get-last-host-error-info)
  (define p (Pa_GetLastHostErrorInfo))
  (and p
       (match (ptr-ref p (_list-struct _int _long _string))
	 [(list api-type error-code error-text)
	  (pa-host-error-info api-type error-code error-text)])))

(define-pa Pa_GetDeviceCount (_fun -> _int))
(define-pa Pa_GetDefaultInputDevice (_fun -> _int))
(define-pa Pa_GetDefaultOutputDevice (_fun -> _int))

(define PaTime _double)

(define PaSampleFormat _ulong)
(define paFloat32        #x00000001)
(define paInt32          #x00000002)
(define paInt24          #x00000004)
(define paInt16          #x00000008)
(define paInt8           #x00000010)
(define paUInt8          #x00000020)
(define paCustomFormat   #x00010000)
(define paNonInterleaved #x80000000)

(struct pa-device-info (name
			host-api
			max-input-channels
			max-output-channels
			default-low-input-latency
			default-low-output-latency
			default-high-input-latency
			default-high-output-latency
			default-sample-rate)
	#:prefab)

(define-pa Pa_GetDeviceInfo (_fun _int -> _pointer))

(define (pa-get-device-info index)
  (define p (Pa_GetDeviceInfo index))
  (and p
       (match (ptr-ref p (_list-struct _int _string _int _int _int PaTime PaTime PaTime PaTime _double))
	 [(list 2 name host-api max-input-channels max-output-channels
		default-low-input-latency default-low-output-latency
		default-high-input-latency default-high-output-latency default-sample-rate)
	  (pa-device-info name host-api max-input-channels max-output-channels
			  default-low-input-latency default-low-output-latency
			  default-high-input-latency default-high-output-latency default-sample-rate)])))

(define-cstruct _PaStreamParameters ([device _int]
				     [channelCount _int]
				     [sampleFormat PaSampleFormat]
				     [suggestedLatency PaTime]
				     [hostApiSpecificStreamInfo _pointer]))

(define-pa Pa_IsFormatSupported (_fun _PaStreamParameters-pointer _PaStreamParameters-pointer _double -> _int))

(define (pa-format-supported? input-parameters output-parameters sample-rate)
  (pa-ok? (Pa_IsFormatSupported input-parameters output-parameters sample-rate)))

(define paFramesPerBufferUnspecified 0)

(define PaStreamFlags _ulong)
(define paNoFlag          0)
(define paClipOff         #x00000001)
(define paDitherOff       #x00000002)
(define paNeverDropInput  #x00000004)
(define paPrimeOutputBuffersUsingStreamCallback #x00000008)
(define paPlatformSpecificFlags #xFFFF0000)

(define PaStreamCallbackFlags _ulong)
(define paInputUnderflow   #x00000001)
(define paInputOverflow    #x00000002)
(define paOutputUnderflow  #x00000004)
(define paOutputOverflow   #x00000008)
(define paPrimingOutput    #x00000010)

(define-cstruct _PaStreamCallbackTimeInfo ([inputBufferAdcTime PaTime]
					   [currentTime PaTime]
					   [outputBufferDacTime PaTime]))

;; PaStreamCallbackResult
(define paContinue 0)
(define paComplete 1)
(define paAbort 2)

(define PaStreamCallback (_fun #:async-apply (lambda (thunk) (thunk))
			       _pointer ;; (const) input
			       _pointer ;; output
			       _ulong ;; frameCount
			       _PaStreamCallbackTimeInfo-pointer
			       PaStreamCallbackFlags
			       _pointer ;; userData
			       -> _int))

(define-pa Pa_OpenStream (_fun (stream : (_ptr o _pointer))
			       _PaStreamParameters-pointer/null ;; inputParameters
			       _PaStreamParameters-pointer/null ;; outputParameters
			       _double ;; sampleRate
			       _ulong ;; framesPerBuffer
			       PaStreamFlags
			       PaStreamCallback
			       _pointer ;; userData
			       -> (status : _int)
			       -> (values status stream)))

(define (pa-open-stream input-parameters output-parameters sample-rate frames-per-buffer flags callback [user-data #f])
  (define-values (status stream)
    (Pa_OpenStream input-parameters output-parameters sample-rate frames-per-buffer flags callback user-data))
  (and (pa-ok? status) stream))

(define-pa Pa_OpenDefaultStream (_fun (stream : (_ptr o _pointer))
				      _int ;; numInputChannels
				      _int ;; numOutputChannels
				      PaSampleFormat
				      _double ;; sampleRate
				      _ulong ;; framesPerBuffer
				      PaStreamCallback
				      _pointer ;; userData
				      -> (status : _int)
				      -> (values status stream)))

(define (pa-open-default-stream num-input-channels num-output-channels
				sample-format sample-rate frames-per-buffer callback [user-data #f])
  (define-values (status stream)
    (Pa_OpenDefaultStream num-input-channels num-output-channels sample-format sample-rate frames-per-buffer callback user-data))
  (and (pa-ok? status) stream))

(define-pa Pa_CloseStream (_fun _pointer -> _int))

(define PaStreamFinishedCallback (_fun _pointer -> _void))

(define-pa Pa_SetStreamFinishedCallback (_fun _pointer PaStreamFinishedCallback -> _int))

(define-pa Pa_StartStream (_fun _pointer -> _int))
(define-pa Pa_StopStream (_fun _pointer -> _int))
(define-pa Pa_AbortStream (_fun _pointer -> _int))
(define-pa Pa_IsStreamStopped (_fun _pointer -> _int))
(define-pa Pa_IsStreamActive (_fun _pointer -> _int))

(define (pa-stream-stopped? stream) (equal? 1 (die-if-error 'Pa_IsStreamStopped (Pa_IsStreamStopped stream))))
(define (pa-stream-active? stream) (equal? 1 (die-if-error 'Pa_IsStreamActive (Pa_IsStreamActive stream))))

(struct pa-stream-info (input-latency output-latency sample-rate) #:prefab)

(define-pa Pa_GetStreamInfo (_fun _pointer -> _pointer))

(define (pa-get-stream-info stream)
  (define p (Pa_GetStreamInfo stream))
  (and p
       (match (ptr-ref p (_list-struct _int PaTime PaTime _double))
	 [(list 1 input-latency output-latency sample-rate)
	  (pa-stream-info input-latency output-latency sample-rate)])))

(define-pa Pa_GetStreamTime (_fun _pointer -> PaTime)) ;; zero on error

(define-pa Pa_GetStreamCpuLoad (_fun _pointer -> _double))

(define-pa Pa_ReadStream (_fun _pointer _bytes _ulong -> _int))
(define-pa Pa_WriteStream (_fun _pointer _bytes _ulong -> _int))

(define-pa Pa_GetStreamReadAvailable (_fun _pointer -> _long))
(define-pa Pa_GetStreamWriteAvailable (_fun _pointer -> _long))

(define-pa Pa_GetSampleSize (_fun PaSampleFormat -> _int))
(define-pa Pa_Sleep (_fun _long -> _void))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(Pa_Initialize)

;; Per the PortAudio documentation, we **MUST** call Pa_Terminate
;; before exiting. Otherwise, on certain systems, serious resource
;; leaks may occur.
(plumber-add-flush! (current-plumber) (lambda (handle)
					(log-info "Calling Pa_Terminate")
					(Pa_Terminate)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(printf "This is PortAudio version ~a.\n" (Pa_GetVersion))
(printf "  - text version: ~a\n" (Pa_GetVersionText))

(printf "API count: ~a\n" (Pa_GetHostApiCount))
(printf "Default API: ~a\n" (Pa_GetDefaultHostApi))
(pa-get-host-api-info (Pa_GetDefaultHostApi))
(pa-get-last-host-error-info)

(printf "Device Count: ~a\n" (Pa_GetDeviceCount))
(printf "Default input device: ~a\n" (Pa_GetDefaultInputDevice))
(printf "Default output device: ~a\n" (Pa_GetDefaultOutputDevice))
(pa-get-device-info (Pa_GetDefaultInputDevice))
(pa-get-device-info (Pa_GetDefaultOutputDevice))

(printf "Stereo input/output on default devices as 16-bit ints at 48kHz supported? ~a\n"
	(pa-format-supported? (make-PaStreamParameters (Pa_GetDefaultInputDevice) 2 paInt16 0.0 #f)
			      (make-PaStreamParameters (Pa_GetDefaultOutputDevice) 2 paInt16 0.0 #f)
			      48000.0))

(define (square-wave-int16 num-channels sample-rate frequency cvec)
  (define len (cvector-length cvec))
  (define half-cycle-period (/ sample-rate (* frequency 2)))
  (let loop ((i 0) (sample-count 0))
    (when (< i len)
      (define half-cycle-number (inexact->exact (truncate (/ sample-count half-cycle-period))))
      (define value (if (odd? half-cycle-number) 32767 -32768))
      (for ((c (in-range i (+ i num-channels)))) (cvector-set! cvec c value))
      (loop (+ i num-channels) (+ sample-count 1)))))

(define (demo-output)
  (define s (pa-open-default-stream
	     0 2 paInt16 48000.0 paFramesPerBufferUnspecified
	     (lambda (in out frame-count time-info-pointer callback-flags user-data)

	       (define inputBufferAdcTime (PaStreamCallbackTimeInfo-inputBufferAdcTime time-info-pointer))
	       (define currentTime (PaStreamCallbackTimeInfo-currentTime time-info-pointer))
	       (define outputBufferDacTime (PaStreamCallbackTimeInfo-outputBufferDacTime time-info-pointer))
	       (printf "frame-count ~a; time-info ~a/~a/~a; flags ~a\n"
		       frame-count
		       inputBufferAdcTime currentTime outputBufferDacTime
		       callback-flags)
	       (flush-output)

	       (define ov (make-cvector* out _short (* frame-count 2))) ;; two channels per frame in this case
	       (square-wave-int16 2 48000 440 ov)

	       paContinue)))
  (printf "Opened stream: ~a\n" s)
  (die-if-error 'Pa_StartStream (Pa_StartStream s))
  (sleep 5)
  (die-if-error 'Pa_StopStream (Pa_StopStream s))
  (die-if-error 'Pa_CloseStream (Pa_CloseStream s)))

(define (cvector-copy c0)
  (define len (cvector-length c0))
  (define c1 (make-cvector (cvector-type c0) len))
  (for ([i len]) (cvector-set! c1 i (cvector-ref c0 i)))
  c1)

(define (demo-input)
  (define chunks '())

  (define s (pa-open-default-stream
	     2 0 paInt16 48000.0 paFramesPerBufferUnspecified
	     (lambda (in out frame-count time-info-pointer callback-flags user-data)
	       (define inputBufferAdcTime (PaStreamCallbackTimeInfo-inputBufferAdcTime time-info-pointer))
	       (define currentTime (PaStreamCallbackTimeInfo-currentTime time-info-pointer))
	       (define outputBufferDacTime (PaStreamCallbackTimeInfo-outputBufferDacTime time-info-pointer))
	       (printf "frame-count ~a; in ~a, out ~a; time-info ~a/~a/~a; flags ~a\n"
		       frame-count
		       in out
		       inputBufferAdcTime currentTime outputBufferDacTime
		       callback-flags)
	       (flush-output)

	       (define chunk (cvector-copy (make-cvector* in _short (* frame-count 2)))) ;; two channels per frame
	       (set! chunks (cons chunk chunks))

	       paContinue)))
  (printf "Opened stream: ~a\n" s)
  (die-if-error 'Pa_StartStream (Pa_StartStream s))
  (sleep 5)
  ;; (die-if-error 'Pa_StopStream (Pa_StopStream s))
  (die-if-error 'Pa_CloseStream (Pa_CloseStream s))
  (with-output-to-file "tmp-out.raw"
    #:exists 'replace
    (lambda ()
      (for* ([chunk (reverse chunks)]
	     [i (cvector-length chunk)])
	(define v (cvector-ref chunk i))
	(write-byte (bitwise-and v 255))
	(write-byte (bitwise-and (arithmetic-shift v -8) 255))))))

(define (u16->s16 x)
  (if (> x 32767)
      (- x 65536)
      x))

(define (safe-cvector-ref v i)
  (if (< i (cvector-length v))
      (cvector-ref v i)
      0))

(define (demo-playback)
  (define input (with-input-from-file "tmp-out.raw"
		  (lambda ()
		    (let loop ((acc '()))
		      (define b1 (read-byte))
		      (define b2 (read-byte))
		      (if (eof-object? b1)
			  (list->cvector (reverse acc) _short)
			  (loop (cons (u16->s16 (+ b1 (* b2 256))) acc)))))))
  (define pos 0)

  (define s (pa-open-default-stream
  	     0 2 paInt16 48000.0 paFramesPerBufferUnspecified
  	     (lambda (in out frame-count time-info-pointer callback-flags user-data)
  	       (define ov (make-cvector* out _short (* frame-count 2))) ;; two channels per frame in this case
	       (for ([i (* frame-count 2)])
		 (cvector-set! ov i (safe-cvector-ref input (+ pos i))))
	       (set! pos (+ pos (* frame-count 2)))
	       (if (< pos (cvector-length input)) paContinue paComplete))))
  (printf "Opened stream: ~a\n" s)
  (die-if-error 'Pa_StartStream (Pa_StartStream s))
  (let loop ()
    (when (pa-stream-active? s)
      (sleep 0.1)
      (loop)))
  (die-if-error 'Pa_CloseStream (Pa_CloseStream s)))

;; (demo-input)
(demo-playback)
