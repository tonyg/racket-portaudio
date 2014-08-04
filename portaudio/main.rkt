#lang racket/base
;; PortAudio FFI wrapper

(provide (struct-out exn:pa)

	 pa-get-version
	 pa-get-version-text

	 (struct-out pa-host-api-info)
	 pa-get-host-api-count
	 pa-get-host-api-info
	 pa-get-default-host-api
	 pa-get-default-host-api-info

	 (struct-out pa-host-error-info)
	 pa-get-last-host-error-info

	 (struct-out pa-device-info)
	 pa-get-device-count
	 pa-get-default-input-device
	 pa-get-default-output-device
	 pa-get-device-info
	 pa-get-default-input-device-info
	 pa-get-default-output-device-info

	 (struct-out pa-stream-parameters)
	 pa-format-supported?

	 ;; Stream flags
	 paNoFlag
	 paClipOff
	 paDitherOff
	 paNeverDropInput
	 paPrimeOutputBuffersUsingStreamCallback
	 paPlatformSpecificFlags

	 pa-stream?
	 pa-stream-input-parameters
	 pa-stream-output-parameters
	 pa-stream-sample-rate
	 pa-stream-frames-per-buffer
	 pa-stream-flags

	 pa-open-input-stream
	 pa-open-output-stream
	 pa-open-input-output-stream

	 pa-default-input-stream
	 pa-default-output-stream
	 pa-default-input-output-stream

	 pa-start-stream
	 pa-stop-stream
	 pa-abort-stream
	 pa-wait-until-stream-inactive
	 pa-close-stream

	 pa-stream-stopped?
	 pa-stream-active?

	 (struct-out pa-stream-info)
	 pa-get-stream-info

	 pa-get-stream-time
	 pa-get-stream-cpu-load
	 pa-read-stream
	 pa-write-stream
	 pa-get-stream-read-available
	 pa-get-stream-write-available
	 pa-get-sample-size
	 )

(require racket/match)
(require ffi/unsafe)
(require ffi/unsafe/define)
(require ffi/unsafe/cvector)
(require (only-in '#%foreign ctype-scheme->c))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main API: structure definitions

(struct exn:pa exn (function-name code text) #:transparent)

(struct pa-host-api-info (index type-id name device-count default-input-device default-output-device) #:prefab)
(struct pa-host-error-info (api-type error-code error-text) #:prefab)
(struct pa-device-info (index
			name
			host-api
			max-input-channels
			max-output-channels
			default-low-input-latency
			default-low-output-latency
			default-high-input-latency
			default-high-output-latency
			default-sample-rate)
	#:prefab)
(struct pa-stream-parameters (device
			      channel-count
			      sample-format
			      suggested-latency) #:prefab)
(struct pa-stream-info (input-latency output-latency sample-rate) #:prefab)

(struct pa-stream (pointer
		   input-parameters
		   output-parameters
		   sample-rate
		   frames-per-buffer
		   flags)) ;; not prefab or transparent

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Low-level: Loading the libportaudio shared library into the FFI

(define pa-lib (ffi-lib "libportaudio" '("2" #f)))

(define-ffi-definer define-pa pa-lib #:default-make-fail make-not-available)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Low-level: definitions and helper functions

(define-pa Pa_GetVersion (_fun -> _int))
(define-pa Pa_GetVersionText (_fun -> _string))
(define-pa Pa_GetErrorText (_fun _int -> _string))

(define (pa-ok? error-code)
  (not (negative? error-code)))

(define (die-if-error function-name error-code)
  (if (pa-ok? error-code)
      error-code
      (let ((text (Pa_GetErrorText error-code)))
	(raise (exn:pa (format "PortAudio error: ~a (code ~a)" text error-code)
		       (current-continuation-marks)
		       function-name
		       error-code
		       text)))))

(define (die-if-error/void function-name error-code)
  (die-if-error function-name error-code)
  (void))

(define _paError (_enum '(paNoError = 0
			  paNotInitialized = -10000
			  paUnanticipatedHostError
			  paInvalidChannelCount
			  paInvalidSampleRate
			  paInvalidDevice
			  paInvalidFlag
			  paSampleFormatNotSupported
			  paBadIODeviceCombination
			  paInsufficientMemory
			  paBufferTooBig
			  paBufferTooSmall
			  paNullCallback
			  paBadStreamPtr
			  paTimedOut
			  paInternalError
			  paDeviceUnavailable
			  paIncompatibleHostApiSpecificStreamInfo
			  paStreamIsStopped
			  paStreamIsNotStopped
			  paInputOverflowed
			  paOutputUnderflowed
			  paHostApiNotFound
			  paInvalidHostApi
			  paCanNotReadFromACallbackStream
			  paCanNotWriteToACallbackStream
			  paCanNotReadFromAnOutputOnlyStream
			  paCanNotWriteToAnInputOnlyStream
			  paIncompatibleStreamHostApi
			  paBadBufferPtr)
			_int))

(define paInputOverflowed ((ctype-scheme->c _paError) 'paInputOverflowed))
(define paOutputUnderflowed ((ctype-scheme->c _paError) 'paOutputUnderflowed))

(define-pa Pa_Initialize (_fun -> _void))
(define-pa Pa_Terminate (_fun -> _void))

(define paNoDevice -1)
(define paUseHostApiSpecificDeviceSpecification -2)

(define-pa Pa_GetHostApiCount (_fun -> _int))
(define-pa Pa_GetDefaultHostApi (_fun -> _int))
(define-pa Pa_GetHostApiInfo (_fun _int -> _pointer))
(define-pa Pa_GetLastHostErrorInfo (_fun -> _pointer))
(define-pa Pa_GetDeviceCount (_fun -> _int))
(define-pa Pa_GetDefaultInputDevice (_fun -> _int))
(define-pa Pa_GetDefaultOutputDevice (_fun -> _int))
(define-pa Pa_GetDeviceInfo (_fun _int -> _pointer))

(define PaTime _double)

(define PaSampleFormat (_bitmask '(paFloat32 =        #x00000001
				   paInt32 =          #x00000002
				   paInt24 =          #x00000004
				   paInt16 =          #x00000008
				   paInt8 =           #x00000010
				   paUInt8 =          #x00000020
				   paCustomFormat =   #x00010000
				   ;; paNonInterleaved = #x80000000 ;; not yet supported
				   )
				 _ulong))

(define-cstruct _PaStreamParameters ([device _int]
				     [channelCount _int]
				     [sampleFormat PaSampleFormat]
				     [suggestedLatency PaTime]
				     [hostApiSpecificStreamInfo _pointer]))

(define (pa-stream-parameters->PaStreamParameters p)
  (match-define (pa-stream-parameters d cc sf sl) p)
  (make-PaStreamParameters d cc sf (ensure-float sl) #f))

(define (ensure-float x)
  (if (inexact? x)
      x
      (exact->inexact x)))

(define-pa Pa_IsFormatSupported (_fun _PaStreamParameters-pointer _PaStreamParameters-pointer _double -> _int))

(define paFramesPerBufferUnspecified 0)

(define PaStreamFlags _ulong)
(define paNoFlag          0)
(define paClipOff         #x00000001)
(define paDitherOff       #x00000002)
(define paNeverDropInput  #x00000004)
(define paPrimeOutputBuffersUsingStreamCallback #x00000008)
(define paPlatformSpecificFlags #xFFFF0000)

(define PaStreamCallbackFlags (_bitmask '(paInputUnderflow =   #x00000001
					  paInputOverflow =    #x00000002
					  paOutputUnderflow =  #x00000004
					  paOutputOverflow =   #x00000008
					  paPrimingOutput =    #x00000010)
					_ulong))

(define-cstruct _PaStreamCallbackTimeInfo ([inputBufferAdcTime PaTime]
					   [currentTime PaTime]
					   [outputBufferDacTime PaTime]))

(define PaStreamCallbackResult (_enum '(paContinue = 0
					paComplete = 1
					paAbort = 2)
				      _int))

(define PaStreamCallback (_fun #:async-apply (lambda (thunk) (thunk))
			       _pointer ;; (const) input
			       _pointer ;; output
			       _ulong ;; frameCount
			       _PaStreamCallbackTimeInfo-pointer
			       PaStreamCallbackFlags
			       _pointer ;; userData
			       -> PaStreamCallbackResult))

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

(define (open-stream input-parameters output-parameters sample-rate frames-per-buffer flags callback [user-data #f])
  (define-values (status stream)
    (Pa_OpenStream input-parameters output-parameters
		   (ensure-float sample-rate)
		   frames-per-buffer flags callback user-data))
  (die-if-error 'Pa_OpenStream status)
  stream)

(define (open-default-stream num-input-channels num-output-channels
			     sample-format sample-rate frames-per-buffer callback [user-data #f])
  (define-values (status stream)
    (Pa_OpenDefaultStream num-input-channels num-output-channels
			  sample-format (ensure-float sample-rate)
			  frames-per-buffer callback user-data))
  (die-if-error 'Pa_OpenDefaultStream status)
  stream)

(define-pa Pa_CloseStream (_fun _pointer -> _int))

(define PaStreamFinishedCallback (_fun _pointer -> _void))

(define-pa Pa_SetStreamFinishedCallback (_fun _pointer PaStreamFinishedCallback -> _int))

(define-pa Pa_StartStream (_fun _pointer -> _int))
(define-pa Pa_StopStream (_fun _pointer -> _int))
(define-pa Pa_AbortStream (_fun _pointer -> _int))
(define-pa Pa_IsStreamStopped (_fun _pointer -> _int))
(define-pa Pa_IsStreamActive (_fun _pointer -> _int))

(define-pa Pa_GetStreamInfo (_fun _pointer -> _pointer))

(define-pa Pa_GetStreamTime (_fun _pointer -> PaTime)) ;; zero on error
(define-pa Pa_GetStreamCpuLoad (_fun _pointer -> _double))
(define-pa Pa_ReadStream (_fun _pointer _bytes _ulong -> _int))
(define-pa Pa_WriteStream (_fun _pointer _bytes _ulong -> _int))
(define-pa Pa_GetStreamReadAvailable (_fun _pointer -> _long))
(define-pa Pa_GetStreamWriteAvailable (_fun _pointer -> _long))
(define-pa Pa_GetSampleSize (_fun PaSampleFormat -> _int))
(define-pa Pa_Sleep (_fun _long -> _void))

(define (compute-frame-size p)
  (* (pa-stream-parameters-channel-count p)
     (pa-get-sample-size (pa-stream-parameters-sample-format p))))

(define (wrap-input-callback callback input-frame-size)
  (and callback
       (lambda (in out frame-count time-info-pointer callback-flags user-data)
	 (callback (make-sized-byte-string in (* frame-count input-frame-size))
		   callback-flags
		   (PaStreamCallbackTimeInfo-currentTime time-info-pointer)
		   (PaStreamCallbackTimeInfo-inputBufferAdcTime time-info-pointer)))))

(define (wrap-output-callback callback output-frame-size)
  (and callback
       (lambda (in out frame-count time-info-pointer callback-flags user-data)
	 (callback (make-sized-byte-string out (* frame-count output-frame-size))
		   callback-flags
		   (PaStreamCallbackTimeInfo-currentTime time-info-pointer)
		   (PaStreamCallbackTimeInfo-outputBufferDacTime time-info-pointer)))))

(define (wrap-input-output-callback callback input-frame-size output-frame-size)
  (and callback
       (lambda (in out frame-count time-info-pointer callback-flags user-data)
	 (callback (make-sized-byte-string in (* frame-count input-frame-size))
		   (make-sized-byte-string out (* frame-count output-frame-size))
		   callback-flags
		   (PaStreamCallbackTimeInfo-currentTime time-info-pointer)
		   (PaStreamCallbackTimeInfo-inputBufferAdcTime time-info-pointer)
		   (PaStreamCallbackTimeInfo-outputBufferDacTime time-info-pointer)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Library initialization and shutdown

(Pa_Initialize)

;; Per the PortAudio documentation, we **MUST** call Pa_Terminate
;; before exiting. Otherwise, on certain systems, serious resource
;; leaks may occur.
(void
 (plumber-add-flush! (current-plumber) (lambda (handle)
					 (log-info "Calling Pa_Terminate")
					 (Pa_Terminate))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main API

(define (pa-get-version) (Pa_GetVersion))
(define (pa-get-version-text) (Pa_GetVersionText))

(define (pa-get-host-api-count) (Pa_GetHostApiCount))

(define (pa-get-host-api-info index)
  (define p (Pa_GetHostApiInfo index))
  (and p
       (match (ptr-ref p (_list-struct _int _int _string _int _int _int))
	 [(list 1 type-id name device-count default-input-device default-output-device)
	  (pa-host-api-info index type-id name device-count default-input-device default-output-device)])))

(define (pa-get-default-host-api) (Pa_GetDefaultHostApi))
(define (pa-get-default-host-api-info) (pa-get-host-api-info (pa-get-default-host-api)))

(define (pa-get-last-host-error-info)
  (define p (Pa_GetLastHostErrorInfo))
  (and p
       (match (ptr-ref p (_list-struct _int _long _string))
	 [(list api-type error-code error-text)
	  (pa-host-error-info api-type error-code error-text)])))

(define (pa-get-device-count) (Pa_GetDeviceCount))
(define (pa-get-default-input-device) (Pa_GetDefaultInputDevice))
(define (pa-get-default-output-device) (Pa_GetDefaultOutputDevice))

(define (pa-get-device-info index)
  (define p (Pa_GetDeviceInfo index))
  (and p
       (match (ptr-ref p (_list-struct _int _string _int _int _int PaTime PaTime PaTime PaTime _double))
	 [(list 2 name host-api max-input-channels max-output-channels
		default-low-input-latency default-low-output-latency
		default-high-input-latency default-high-output-latency default-sample-rate)
	  (pa-device-info index name host-api max-input-channels max-output-channels
			  default-low-input-latency default-low-output-latency
			  default-high-input-latency default-high-output-latency default-sample-rate)])))

(define (pa-get-default-input-device-info) (pa-get-device-info (pa-get-default-input-device)))
(define (pa-get-default-output-device-info) (pa-get-device-info (pa-get-default-output-device)))

(define (pa-format-supported? input-parameters output-parameters sample-rate)
  (pa-ok? (Pa_IsFormatSupported (pa-stream-parameters->PaStreamParameters input-parameters)
				(pa-stream-parameters->PaStreamParameters output-parameters)
				(ensure-float sample-rate))))

(define (pa-open-input-stream input-parameters sample-rate frames-per-buffer flags callback)
  (define frame-size (compute-frame-size input-parameters))
  (pa-stream (open-stream (pa-stream-parameters->PaStreamParameters input-parameters)
			  #f
			  sample-rate
			  (or frames-per-buffer paFramesPerBufferUnspecified)
			  flags
			  (wrap-input-callback callback frame-size))
	     input-parameters
	     #f
	     sample-rate
	     (or frames-per-buffer paFramesPerBufferUnspecified)
	     flags))

(define (pa-open-output-stream output-parameters sample-rate frames-per-buffer flags callback)
  (define frame-size (compute-frame-size output-parameters))
  (pa-stream (open-stream #f
			  (pa-stream-parameters->PaStreamParameters output-parameters)
			  sample-rate
			  (or frames-per-buffer paFramesPerBufferUnspecified)
			  flags
			  (wrap-output-callback callback frame-size))
	     #f
	     output-parameters
	     sample-rate
	     (or frames-per-buffer paFramesPerBufferUnspecified)
	     flags))

(define (pa-open-input-output-stream input-parameters output-parameters sample-rate frames-per-buffer flags callback)
  (define input-frame-size (compute-frame-size input-parameters))
  (define output-frame-size (compute-frame-size output-parameters))
  (pa-stream (open-stream (pa-stream-parameters->PaStreamParameters input-parameters)
			  (pa-stream-parameters->PaStreamParameters output-parameters)
			  sample-rate
			  (or frames-per-buffer paFramesPerBufferUnspecified)
			  flags
			  (wrap-input-output-callback callback input-frame-size output-frame-size))
	     input-parameters
	     output-parameters
	     sample-rate
	     (or frames-per-buffer paFramesPerBufferUnspecified)
	     flags))

(define (pa-default-input-stream num-input-channels sample-format sample-rate frames-per-buffer callback)
  (define i (pa-get-default-input-device-info))
  (define il (pa-device-info-default-high-input-latency i))
  (pa-open-input-stream (pa-stream-parameters (pa-get-default-input-device) num-input-channels sample-format il)
			sample-rate
			frames-per-buffer
			0
			callback))

(define (pa-default-output-stream num-output-channels sample-format sample-rate frames-per-buffer callback)
  (define o (pa-get-default-output-device-info))
  (define ol (pa-device-info-default-high-output-latency o))
  (pa-open-output-stream (pa-stream-parameters (pa-get-default-output-device) num-output-channels sample-format ol)
			 sample-rate
			 frames-per-buffer
			 0
			 callback))

(define (pa-default-input-output-stream num-input-channels num-output-channels sample-format sample-rate frames-per-buffer callback)
  (define i (pa-get-default-input-device-info))
  (define il (pa-device-info-default-high-input-latency i))
  (define o (pa-get-default-output-device-info))
  (define ol (pa-device-info-default-high-output-latency o))
  (pa-open-input-output-stream (pa-stream-parameters (pa-get-default-input-device) num-input-channels sample-format il)
			       (pa-stream-parameters (pa-get-default-output-device) num-output-channels sample-format ol)
			       sample-rate
			       frames-per-buffer
			       0
			       callback))

(define (pa-start-stream s) (die-if-error/void 'pa-start-stream (Pa_StartStream (pa-stream-pointer s))))
(define (pa-stop-stream s) (die-if-error/void 'pa-stop-stream (Pa_StopStream (pa-stream-pointer s))))
(define (pa-abort-stream s) (die-if-error/void 'pa-abort-stream (Pa_AbortStream (pa-stream-pointer s))))

(define (pa-wait-until-stream-inactive s)
  (when (pa-stream-active? s)
    (sleep 0.1)
    (pa-wait-until-stream-inactive s)))

(define (pa-close-stream s) (die-if-error/void 'pa-close-stream (Pa_CloseStream (pa-stream-pointer s))))

(define (pa-stream-stopped? stream)
  (equal? 1 (die-if-error 'pa-stream-stopped? (Pa_IsStreamStopped (pa-stream-pointer stream)))))
(define (pa-stream-active? stream)
  (equal? 1 (die-if-error 'pa-stream-active? (Pa_IsStreamActive (pa-stream-pointer stream)))))

(define (pa-get-stream-info stream)
  (define p (Pa_GetStreamInfo (pa-stream-pointer stream)))
  (and p
       (match (ptr-ref p (_list-struct _int PaTime PaTime _double))
	 [(list 1 input-latency output-latency sample-rate)
	  (pa-stream-info input-latency output-latency sample-rate)])))

(define (pa-get-stream-time s)
  (die-if-error 'pa-get-stream-time (Pa_GetStreamTime (pa-stream-pointer s))))
(define (pa-get-stream-cpu-load s)
  (die-if-error 'pa-get-stream-cpu-load (Pa_GetStreamCpuLoad (pa-stream-pointer s))))

(define (pa-read-stream s frame-count)
  (define frame-size (compute-frame-size (pa-stream-input-parameters s)))
  (define buffer (make-bytes (* frame-count frame-size) 0))
  (match (Pa_ReadStream (pa-stream-pointer s) buffer frame-count)
    [0 (values #f buffer)]
    [(== paInputOverflowed) (values #t buffer)]
    [other (die-if-error 'pa-read-stream other)]))

(define (pa-write-stream s buffer)
  (define frame-size (compute-frame-size (pa-stream-output-parameters s)))
  (define buffer-length (bytes-length buffer))
  (when (not (zero? (remainder buffer-length frame-size)))
    (error 'pa-write-stream
	   "Buffer length ~a not a multiple of frame-size ~a"
	   buffer-length
	   frame-size))
  (define frame-count (quotient buffer-length frame-size))
  (match (Pa_WriteStream (pa-stream-pointer s) buffer frame-count)
    [0 #f]
    [(== paOutputUnderflowed) #t]
    [other (die-if-error 'pa-write-stream other)]))

(define (pa-get-stream-read-available s)
  (die-if-error 'pa-get-stream-read-available
		(Pa_GetStreamReadAvailable (pa-stream-pointer s))))

(define (pa-get-stream-write-available s)
  (die-if-error 'pa-get-stream-write-available
		(Pa_GetStreamWriteAvailable (pa-stream-pointer s))))

(define (pa-get-sample-size sf)
  (die-if-error 'pa-get-sample-size (Pa_GetSampleSize sf)))
