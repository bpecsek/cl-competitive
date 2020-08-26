;;;
;;; Compute binomial coefficient by direct bignum arithmetic
;;;

(defpackage :cp/binomial-coefficient
  (:use :cl)
  (:export #:factorial #:binomial-coefficient))
(in-package :cp/binomial-coefficient)

;; dead copy of alexandria::%multiply-range
(declaim (inline %multiply-range))
(defun %multiply-range (i j)
  (labels ((bisect (j k)
             (declare (type (integer 1 #.most-positive-fixnum) j k)
                      (values integer))
             (if (< (- k j) 8)
                 (multiply-range j k)
                 (let ((middle (+ j (truncate (- k j) 2))))
                   (* (bisect j middle)
                      (bisect (+ middle 1) k)))))
           (multiply-range (j k)
             (declare (type (integer 1 #.most-positive-fixnum) j k))
             (do ((f k (* f m))
                  (m (1- k) (1- m)))
                 ((< m j) f)
               (declare (type (integer 0 (#.most-positive-fixnum)) m)
                        (type unsigned-byte f)))))
    (bisect i j)))

(declaim (inline factorial))
(defun factorial (n)
  (cond ((< n 0) 0)
        ((zerop n) 1)
        (t (%multiply-range 1 n))))

(defun binomial-coefficient (n k)
  (declare (fixnum n k))
  (cond ((or (< n 0) (< k 0) (< n k)) 0)
        ((or (zerop k) (= n k)) 1)
        (t (let ((n-k (- n k)))
             (when (< k n-k)
               (rotatef k n-k))
             (if (= 1 n-k)
                 n
                 (floor (%multiply-range (+ k 1) n)
	                (%multiply-range 1 n-k)))))))