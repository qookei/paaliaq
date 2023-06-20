(define-module (as-helper toplevel) #: export (proc far-proc extern flat-binary))
(use-modules (ice-9 match) (srfi srfi-26) (as-helper relocate)
	     (as-helper assemble) (as-helper utility))

(define (build-frame-env return-size params locals)
  (let ((items `(,@locals (!!return-addr . ,return-size) ,@params))
	(cur-offset 1)
	(env '()))
    (while (not (null? items))
      (set! env `(,@env (,(caar items) . ,cur-offset)))
      (set! cur-offset (+ cur-offset (cdar items)))
      (set! items (cdr items)))
    env))

(define-syntax define-proc-syntax
  (syntax-rules ::: ()
    ((_ proc-kind proc-ret-size)
     (define-syntax proc-kind
       (syntax-rules ()
	 ((_ name params locals body ...)
	  (match-let (((bytes relocs labels) (assemble `(body ...))))
	    `(,'name . ((data . ,bytes)
			(local-relocs . ,relocs)
			(local-labels . ,labels)
			(priv-env . ,(build-frame-env proc-ret-size `params `locals)))))))))))

(define-proc-syntax proc 2)
(define-proc-syntax far-proc 3)

(define-syntax extern
  (syntax-rules ()
    ((_ name addr)
     `(() . ((pub-env . (,'name . ,addr)))))))

(define (offset-relocation reloc by)
  (match reloc
    (('reloc-abs offset stack-off sz expr)
     `(reloc-abs ,(+ by offset) ,stack-off ,sz ,expr))
    (('reloc-frame-rel offset stack-off sz expr)
     `(reloc-frame-rel ,(+ by offset) ,stack-off ,sz ,expr))
    (('reloc-branch offset stack-off sz expr)
     `(reloc-branch ,(+ by offset) ,stack-off ,sz ,expr))))

(define (offset-label label-cell by)
  (cons (car label-cell) (+ by (cdr label-cell))))

(define (append-entry data entry)
  (let ((offset (length data)) (entry-name (car entry)) (entry-data (cdr entry)))
    `(,(append data (assoc-get-or-default 'data entry-data '()))
      (,entry-name
       (offset . ,offset)
       (data . ,(assoc-get-or-default 'data entry-data '()))
       (local-relocs . ,(map (cut offset-relocation <> offset) (assoc-get-or-default 'local-relocs entry-data '())))
       (local-labels . ,(map (cut offset-label <> offset) (assoc-get-or-default 'local-labels entry-data '())))
       (priv-env . ,(assoc-get-or-default 'priv-env entry-data '()))
       (pub-env  . ,(assoc-get-or-default 'pub-env entry-data '()))))))

(define (nonnull-in-list? table key)
  (match (assoc key table)
    ((k . v) (not (null? v))) (_ #f)))

(define (build-global-symbol-table base entries)
  (map-in-order
   (lambda (entry)
     (if (nonnull-in-list? (cdr entry) 'pub-env)
	 (assoc-get-or-default 'pub-env (cdr entry) '())
	 `(,(car entry) . ,(+ base (assoc-get-or-default 'offset (cdr entry) 0)))))
   entries))

(define (flat-binary base-addr . entries)
  (let ((data '()) (actual-entries '()))
    (for-each
     (lambda (entry)
       (match-let (((new-data new-entry) (append-entry data entry)))
	 (set! actual-entries (cons new-entry actual-entries))
	 (set! data new-data)))
     entries)

    (let ((symbol-table (build-global-symbol-table base-addr actual-entries)))
      (for-each
       (lambda (entry)
	 (set! data
	       (relocate
		base-addr
		`(,@symbol-table
		  ,@(assoc-get-or-default 'priv-env (cdr entry) '()))
		data
		(assoc-get-or-default 'local-relocs (cdr entry) '())
		(assoc-get-or-default 'local-labels (cdr entry) '()))))
       actual-entries)
      data)))
