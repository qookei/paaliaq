(define-module (as-helper utility) #: export
 (value-to-n-bytes compute-branch-target assoc-get-or-default))
(use-modules (ice-9 match) (srfi srfi-1) (srfi srfi-26))

(define (branch-target-fits? offset len)
 (match len
  ('1 (and (>= offset -128) (< offset 128)))
  ('2 (and (>= offset -32768) (< offset 32768)))
  (_ (error "Illegal branch target width:" len))))

(define (compute-branch-target pc len target)
 ;; Target is computed relative to after the instruction
 (let ((offset (- target (+ pc len))))
  (if (branch-target-fits? offset len)
   (value-to-n-bytes offset len)
   (error "Branch target out of range:" offset))))

(define (value-to-n-bytes value n)
 (map (lambda (i)
   (logand (ash value (* i -8)) #xff))
  (iota n)))

(define (assoc-get-or-default name env default)
 (match (assoc name env)
  ((k . v) v)
  (_ default)))




