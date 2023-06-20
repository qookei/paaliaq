(define-module (as-helper relocate) #: export (relocate))
(use-modules (ice-9 match) (srfi srfi-1) (srfi srfi-26) (as-helper utility))

(define (relocate-label base-addr label-cell)
  (cons (car label-cell) (+ base-addr (cdr label-cell))))

(define (lookup-in-env name env)
  (match (assoc name env)
    ((k . v) v)
    (_ (error "Name not found in environment:" name))))


(define (eval-reloc-expr pc stack-off expr env)
  (match expr
    ('$ pc)
    ('$frame stack-off)
    ((? number? val) val)
    ((? string? val) val)
    ((? symbol? name) (lookup-in-env name env))
    (('bank expr) (logand (ash (eval-reloc-expr pc stack-off expr env) -16) #xff))
    (('local-addr expr) (logand (eval-reloc-expr pc stack-off expr env) #xffff))
    (('in-frame expr) (+ (eval-reloc-expr pc stack-off expr env) stack-off))
    (('+ expr by) (+ (eval-reloc-expr pc stack-off expr env) (eval-reloc-expr pc stack-off by env)))
    (('- expr by) (- (eval-reloc-expr pc stack-off expr env) (eval-reloc-expr pc stack-off by env)))
    (('<< expr by) (ash (eval-reloc-expr pc stack-off expr env) (eval-reloc-expr pc stack-off by env)))
    (('>> expr by) (ash (eval-reloc-expr pc stack-off expr env) (- (eval-reloc-expr pc stack-off by env))))
    (('| expr by) (logior (eval-reloc-expr pc stack-off expr env) (eval-reloc-expr pc stack-off by env)))
    (('& expr by) (logand (eval-reloc-expr pc stack-off expr env) (eval-reloc-expr pc stack-off by env)))
    (('^ expr by) (logxor (eval-reloc-expr pc stack-off expr env) (eval-reloc-expr pc stack-off by env)))
    (('far bank addr) (logior (ash (eval-reloc-expr pc stack-off bank env) 16) (eval-reloc-expr pc stack-off addr env)))))

(define (apply-patch-to-bytes bytes off patch)
  `(,@(take bytes off) ,@patch ,@(drop bytes (+ (length patch) off))))

(define (relocate base-addr global-env bytes relocs local-env)
  (let ((env `(,@global-env
	       ,@(map (cut relocate-label base-addr <>) local-env)))
	(cur-relocs relocs) (cur-bytes bytes))
    (while (not (null? cur-relocs))
      (match (car cur-relocs)
	(('reloc-abs offset stack-off sz expr)
	 (set! cur-bytes
	       (apply-patch-to-bytes
		cur-bytes offset
		(value-to-n-bytes (eval-reloc-expr
				   (+ offset base-addr -1) stack-off expr env) sz))))
	(('reloc-frame-rel offset stack-off sz expr)
	 (set! cur-bytes
	       (apply-patch-to-bytes
		cur-bytes offset
		(value-to-n-bytes (+ stack-off (eval-reloc-expr
						(+ offset base-addr -1) stack-off expr env)) sz))))
	(('reloc-branch offset stack-off sz expr)
	 (set! cur-bytes
	       (apply-patch-to-bytes
		cur-bytes offset
		(compute-branch-target
		 (+ offset base-addr) sz
		 (eval-reloc-expr (+ offset base-addr -1) stack-off expr env))))))
      (set! cur-relocs (cdr cur-relocs)))
    cur-bytes))
