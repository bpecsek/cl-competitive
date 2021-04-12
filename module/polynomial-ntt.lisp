(defpackage :cp/polynomial-ntt
  (:use :cl :cp/ntt)
  (:export #:poly-multiply #:poly-inverse #:poly-floor #:poly-mod #:poly-sub #:poly-add
           #:multipoint-eval #:poly-total-prod #:chirp-z #:bostan-mori))
(in-package :cp/polynomial-ntt)

;; TODO: integrate with cp/polynomial

(define-ntt +ntt-mod+
  :convolve poly-multiply
  :mod-inverse %mod-inverse
  :mod-power %mod-power)

;; (declaim (ftype (function * (values ntt-vector &optional)) poly-inverse))
;; (defun poly-inverse (poly &optional result-length)
;;   (declare (optimize (speed 3))
;;            (vector poly)
;;            ((or null fixnum) result-length))
;;   (let* ((poly (coerce poly 'ntt-vector))
;;          (n (length poly)))
;;     (declare (ntt-vector poly))
;;     (when (or (zerop n)
;;               (zerop (aref poly 0)))
;;       (error 'division-by-zero
;;              :operation #'poly-inverse
;;              :operands (list poly)))
;;     (let ((res (make-array 1
;;                            :element-type 'ntt-int
;;                            :initial-element (%mod-inverse (aref poly 0))))
;;           (result-length (or result-length n)))
;;       (declare (ntt-vector res))
;;       (loop for i of-type ntt-int = 1 then (ash i 1)
;;             while (< i result-length)
;;             for decr = (poly-multiply (poly-multiply res res)
;;                                       (subseq poly 0 (min (length poly) (* 2 i))))
;;             for decr-len = (length decr)
;;             do (setq res (adjust-array res (* 2 i) :initial-element 0))
;;                (dotimes (j (* 2 i))
;;                  (setf (aref res j)
;;                        (mod (the ntt-int
;;                                  (+ (mod (* 2 (aref res j)) +ntt-mod+)
;;                                     (if (>= j decr-len) 0 (- +ntt-mod+ (aref decr j)))))
;;                             +ntt-mod+))))
;;       (adjust-array res result-length))))

;; Reference: https://opt-cp.com/fps-fast-algorithms/
(declaim (ftype (function * (values ntt-vector &optional)) poly-inverse))
(defun poly-inverse (poly &optional result-length)
  (declare (optimize (speed 3))
           (vector poly)
           ((or null fixnum) result-length))
  (let* ((poly (coerce poly 'ntt-vector))
         (n (length poly)))
    (declare (ntt-vector poly))
    (when (or (zerop n)
              (zerop (aref poly 0)))
      (error 'division-by-zero
             :operation #'poly-inverse
             :operands (list poly)))
    (let* ((result-length (or result-length n))
           (res (make-array 1
                            :element-type 'ntt-int
                            :initial-element (%mod-inverse (aref poly 0)))))
      (declare (ntt-vector res))
      (loop for i of-type ntt-int = 1 then (ash i 1)
            while (< i result-length)
            for f of-type ntt-vector = (subseq poly 0 (min n (* 2 i)))
            for g of-type ntt-vector = (copy-seq res)
            do (setq f (adjust-array f (* 2 i) :initial-element 0)
                     g (adjust-array g (* 2 i) :initial-element 0))
               (ntt! f)
               (ntt! g)
               (dotimes (j (* 2 i))
                 (setf (aref f j) (mod (* (aref g j) (aref f j)) +ntt-mod+)))
               (inverse-ntt! f)
               (setq f (subseq f i (* 2 i)))
               (setq f (adjust-array f (* 2 i) :initial-element 0))
               (ntt! f)
               (dotimes (j (* 2 i))
                 (setf (aref f j) (mod (* (aref g j) (aref f j)) +ntt-mod+)))
               (inverse-ntt! f)
               (let ((inv-len (%mod-inverse (* 2 i))))
                 (setq inv-len (mod (* inv-len (- +ntt-mod+ inv-len))
                                    +ntt-mod+))
                 (dotimes (j i)
                   (setf (aref f j) (mod (* inv-len (aref f j)) +ntt-mod+)))
                 (setq res (adjust-array res (* 2 i)))
                 (replace res f :start1 i)))
      (adjust-array res result-length))))

(declaim (ftype (function * (values ntt-vector &optional)) poly-floor))
(defun poly-floor (poly1 poly2)
  (declare (optimize (speed 3))
           (vector poly1 poly2))
  (let* ((poly1 (coerce poly1 'ntt-vector))
         (poly2 (coerce poly2 'ntt-vector))
         (deg1 (+ 1 (or (position 0 poly1 :from-end t :test-not #'eql) -1)))
         (deg2 (+ 1 (or (position 0 poly2 :from-end t :test-not #'eql) -1))))
    (when (> deg2 deg1)
      (return-from poly-floor (make-array 0 :element-type 'ntt-int)))
    (setq poly1 (nreverse (subseq poly1 0 deg1))
          poly2 (nreverse (subseq poly2 0 deg2)))
    (let* ((res-len (+ 1 (- deg1 deg2)))
           (res (adjust-array (poly-multiply poly1 (poly-inverse poly2 res-len))
                              res-len)))
      (nreverse res))))

(declaim (ftype (function * (values ntt-vector &optional)) poly-sub))
(defun poly-sub (poly1 poly2)
  (declare (optimize (speed 3))
           (vector poly1 poly2))
  (let* ((poly1 (coerce poly1 'ntt-vector))
         (poly2 (coerce poly2 'ntt-vector))
         (len (max (length poly1) (length poly2)))
         (res (make-array len :element-type 'ntt-int :initial-element 0)))
    (replace res poly1)
    (dotimes (i (length poly2))
      (let ((value (+ (aref res i)
                      (the ntt-int (- +ntt-mod+ (aref poly2 i))))))
        (setf (aref res i)
              (if (>= value +ntt-mod+)
                  (- value +ntt-mod+)
                  value))))
    (let ((end (+ 1 (or (position 0 res :from-end t :test-not #'eql) -1))))
      (adjust-array res end))))

(declaim (ftype (function * (values ntt-vector &optional)) poly-add))
(defun poly-add (poly1 poly2)
  (declare (optimize (speed 3))
           (vector poly1 poly2))
  (let* ((poly1 (coerce poly1 'ntt-vector))
         (poly2 (coerce poly2 'ntt-vector))
         (len (max (length poly1) (length poly2)))
         (res (make-array len :element-type 'ntt-int :initial-element 0)))
    (replace res poly1)
    (dotimes (i (length poly2))
      (let ((value (+ (aref res i) (aref poly2 i))))
        (setf (aref res i)
              (if (>= value +ntt-mod+)
                  (- value +ntt-mod+)
                  value))))
    (let ((end (+ 1 (or (position 0 res :from-end t :test-not #'eql) -1))))
      (adjust-array res end))))

(declaim (ftype (function * (values ntt-vector &optional)) poly-mod))
(defun poly-mod (poly1 poly2)
  (declare (optimize (speed 3))
           (vector poly1 poly2))
  (let ((poly1 (coerce poly1 'ntt-vector))
        (poly2 (coerce poly2 'ntt-vector)))
    (when (loop for x across poly1 always (zerop x))
      (return-from poly-mod (make-array 0 :element-type 'ntt-int)))
    (let* ((res (poly-sub poly1 (poly-multiply (poly-floor poly1 poly2) poly2)))
           (end (+ 1 (or (position 0 res :from-end t :test-not #'eql) -1))))
      (subseq res 0 end))))

(declaim (ftype (function * (values ntt-vector &optional)) poly-total-prod))
(defun poly-total-prod (polys)
  "Returns the total polynomial product: polys[0] * polys[1] * ... * polys[n-1]."
  (declare (vector polys))
  (let* ((n (length polys))
         (dp (make-array n :element-type t)))
    (declare ((mod #.array-total-size-limit) n))
    (when (zerop n)
      (return-from poly-total-prod (make-array 1 :element-type 'ntt-int :initial-element 1)))
    (replace dp polys)
    (loop for width of-type (mod #.array-total-size-limit) = 1 then (ash width 1)
          while (< width n)
          do (loop for i of-type (mod #.array-total-size-limit) from 0 by (* width 2)
                   while (< (+ i width) n)
                   do (setf (aref dp i)
                            (poly-multiply (aref dp i) (aref dp (+ i width))))))
    (coerce (aref dp 0) 'ntt-vector)))

(declaim (ftype (function * (values ntt-vector &optional)) multipoint-eval))
(defun multipoint-eval (poly points)
  "The length of POINTS must be a power of two."
  (declare (optimize (speed 3))
           (vector poly points)
           #+sbcl (sb-ext:muffle-conditions style-warning))
  (check-ntt-vector points)
  (let* ((poly (coerce poly 'ntt-vector))
         (points (coerce points 'ntt-vector))
         (len (length points))
         (table (make-array (max 0 (- (* 2 len) 1)) :element-type 'ntt-vector))
         (res (make-array len :element-type 'ntt-int)))
    (unless (zerop len)
      (labels ((%build (l r pos)
                 (declare ((mod #.array-total-size-limit) l r pos))
                 (if (= (- r l) 1)
                     (let ((lin (make-array 2 :element-type 'ntt-int)))
                       (setf (aref lin 0) (- +ntt-mod+ (aref points l)) ;; NOTE: non-zero
                             (aref lin 1) 1)
                       (setf (aref table pos) lin))
                     (let ((mid (ash (+ l r) -1)))
                       (%build l mid (+ 1 (* pos 2)))
                       (%build mid r (+ 2 (* pos 2)))
                       (setf (aref table pos)
                             (poly-multiply (aref table (+ 1 (* pos 2)))
                                            (aref table (+ 2 (* pos 2)))))))))
        (%build 0 len 0))
      (labels ((%eval (poly l r pos)
                 (declare ((mod #.array-total-size-limit) l r pos))
                 (if (= (- r l) 1)
                     (let ((tmp (poly-mod poly (aref table pos))))
                       (setf (aref res l) (if (zerop (length tmp)) 0 (aref tmp 0))))
                     (let ((mid (ash (+ l r) -1)))
                       (%eval (poly-mod poly (aref table (+ (* 2 pos) 1)))
                              l mid (+ (* 2 pos) 1))
                       (%eval (poly-mod poly (aref table (+ (* 2 pos) 2)))
                              mid r (+ (* 2 pos) 2))))))
        (%eval poly 0 len 0)))
    res))

;; not tested
(declaim (ftype (function * (values ntt-vector &optional)) chirp-z))
(defun chirp-z (poly base length)
  "Does multipoint evaluation of POLY with powers of BASE: P(base^0), P(base^1), ...,
P(base^(length-1)). BASE must be coprime with modulus. Time complexity is
O((N+MOD)log(N+MOD)).

Reference:
https://codeforces.com/blog/entry/83532"
  (declare (optimize (speed 3))
           (vector poly)
           (ntt-int base length))
  (when (zerop (length poly))
    (return-from chirp-z (make-array length :element-type 'ntt-int :initial-element 0)))
  (let* ((poly (coerce poly 'ntt-vector))
         (binv (%mod-inverse base))
         (n (length poly))
         (m (max length n))
         (n+m (+ n m))
         (cs (make-array n :element-type 'ntt-int :initial-element 0))
         (ds (make-array n+m :element-type 'ntt-int :initial-element 0)))
    (declare (ntt-int n m n+m))
    (dotimes (i n)
      (setf (aref cs i) (mod (* (aref poly (- n 1 i))
                                (%mod-power binv (ash (* (- n 1 i) (- n 2 i)) -1)))
                             +ntt-mod+)))
    (dotimes (i n+m)
      (setf (aref ds i) (%mod-power base (ash (* i (- i 1)) -1))))
    (let ((result (subseq (poly-multiply cs ds)
                          (- n 1)
                          (+ (- n 1) length))))
      (dotimes (i length)
        (setf (aref result i)
              (mod (* (aref result i)
                      (%mod-power binv (ash (* i (- i 1)) -1)))
                   +ntt-mod+)))
      result)))

(declaim (ftype (function * (values ntt-int &optional)) bostan-mori))
(defun bostan-mori (index num denom)
  "Returns [x^index]num(x)/denom(x). Time compexity is 

Reference:
https://arxiv.org/abs/2008.08822
https://qiita.com/ryuhe1/items/da5acbcce4ac1911f47 (Japanese)"
  (declare (optimize (speed 3))
           (unsigned-byte index)
           (vector num denom))
  (labels ((even (p)
             (let ((res (make-array (ceiling (length p) 2) :element-type 'ntt-int)))
               (dotimes (i (length res))
                 (setf (aref res i)
                       (aref p (* 2 i))))
               res))
           (odd (p)
             (let ((res (make-array (floor (length p) 2) :element-type 'ntt-int)))
               (dotimes (i (length res))
                 (setf (aref res i) (aref p (+ 1 (* 2 i)))))
               res))
           (negate (p)
             (let ((res (copy-seq p)))
               (loop for i from 1 below (length res) by 2
                     do (setf (aref res i)
                              (if (zerop (aref res i))
                                  0
                                  (- +ntt-mod+ (aref res i)))))
               res)))
    (let ((num (coerce num 'ntt-vector))
          (denom (coerce denom 'ntt-vector)))
      (assert (and (>= (length denom) 1)
                   (>= (length num) 1)
                   (not (zerop (aref denom 0)))))
      (loop while (> index 0)
            for denom- = (negate denom)
            for u = (poly-multiply num denom-)
            when (evenp index)
            do (setq num (even u))
            else
            do (setq num (odd u))
            do (setq denom (even (poly-multiply denom denom-))
                     index (ash index -1))
            finally (return (mod (* (aref num 0)
                                    (%mod-inverse (aref denom 0)))
                                 +ntt-mod+))))))
