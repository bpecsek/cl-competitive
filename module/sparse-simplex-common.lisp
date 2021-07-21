(defpackage :cp/sparse-simplex-common
  (:use :cl :cp/csc :cp/lud)
  (:import-from :cp/csc #:+zero+ #:+one+ #:csc-float)
  (:import-from :cp/lud #:vector-set* #:extend-vectorf)
  (:use :cl)
  (:export #:make-dictionary #:dictionary-swap! #:dot* #:tmat-times-vec!
           #:make-sparse-lp #:slp-restore #:slp-lude #:slp-m #:slp-n #:slp-dictionary
           #:slp-mat #:slp-tmat #:slp-b #:slp-c #:slp-x-basic #:slp-y-nonbasic
           #:correct-x-basic! #:correct-y-nonbasic!
           #:dictionary-basics #:dictionary-nonbasics #:dictionary-basic-flag))
(in-package :cp/sparse-simplex-common)

(defconstant +eps+ (coerce 1d-8 'csc-float))

(defun add-slack! (a)
  (declare (optimize (speed 3))
           (csc a))
  (symbol-macrolet ((m (csc-m a))
                    (n (csc-n a))
                    (colstarts (csc-colstarts a))
                    (rows (csc-rows a))
                    (values (csc-values a))
                    (nz (csc-nz a)))
    ;; Add slack variable
    (loop for row below m
          for col of-type (mod #.array-dimension-limit) from n
          for k from (aref colstarts n)
          do (vector-set* values k +one+)
             (vector-set* rows k row)
             (vector-set* colstarts (+ col 1) (+ k 1))
             (incf nz)
          finally (setf n (+ n m)))
    a))

(defstruct (dictionary (:constructor %make-dictionary))
  (m nil :type (mod #.array-dimension-limit))
  (n nil :type (mod #.array-dimension-limit))
  (basics nil :type (simple-array fixnum (*)))
  (nonbasics nil :type (simple-array fixnum (*)))
  (basic-flag nil :type (simple-array fixnum (*))))

(defconstant +nan+ most-positive-fixnum)
(defun make-dictionary (m n basics)
  "BASICS[i] = column number of the constraints matrix (of size m * (n + m))
which is currently basic.

0, 1, 2, ....., n-1, n, n+1, ..., n+m-1
|- non-slack vars -| |-- slack vars --|
"
  (declare (optimize (speed 3))
           (vector basics)
           ((mod #.array-dimension-limit) m n))
  (let* ((basics (coerce basics '(simple-array fixnum (*))))
         (basic-flag (make-array (+ n m) :element-type 'fixnum :initial-element +nan+))
         (nonbasics (make-array n :element-type 'fixnum)))
    (dotimes (i m)
      (let ((col (aref basics i)))
        (setf (aref basic-flag col) i)))
    (let ((j 0))
      (dotimes (col (length basic-flag))
        (when (= (aref basic-flag col) +nan+)
          (setf (aref nonbasics j) col
                (aref basic-flag col) (lognot j))
          (incf j))))
    (%make-dictionary :m m :n n :basics basics :nonbasics nonbasics :basic-flag basic-flag)))

(defun dictionary-swap! (dictionary col-out col-in)
  (declare (optimize (speed 3))
           ((mod #.array-dimension-limit) col-out col-in))
  (let* ((basics (dictionary-basics dictionary))
         (nonbasics (dictionary-nonbasics dictionary))
         (basic-flag (dictionary-basic-flag dictionary))
         (i (aref basics col-out))
         (j (aref nonbasics col-in)))
    (setf (aref basics col-out) j
          (aref nonbasics col-in) i
          (aref basic-flag i) (lognot col-in)
          (aref basic-flag j) col-out))
  dictionary)

(defstruct (sparse-lp (:constructor %make-sparse-lp)
                      (:conc-name slp-))
  (m nil :type (mod #.array-dimension-limit))
  (n nil :type (mod #.array-dimension-limit))
  (mat nil :type csc)
  (tmat nil :type csc)
  (b nil :type (simple-array csc-float (*)))
  (c nil :type (simple-array csc-float (*)))
  (x-basic nil :type (simple-array csc-float (*)))
  (y-nonbasic nil :type (simple-array csc-float (*)))
  (dictionary nil :type dictionary)
  (lude nil :type lud-eta))

(defun correct-x-basic! (lude x-basic)
  (assert (zerop (lud-eta-count lude)))
  (dense-solve! (lud-eta-lud lude) x-basic))

(defun correct-y-nonbasic! (sparse-lp)
  (declare (optimize (speed 3)))
  (let* ((lude (slp-lude sparse-lp))
         (m (slp-m sparse-lp))
         (n (slp-n sparse-lp))
         (tmat (slp-tmat sparse-lp))
         (c (slp-c sparse-lp))
         (tmp (make-sparse-vector m))
         (dictionary (slp-dictionary sparse-lp))
         (basics (dictionary-basics dictionary))
         (nonbasics (dictionary-nonbasics dictionary))
         (basic-flag (dictionary-basic-flag dictionary))
         (y-nonbasic (slp-y-nonbasic sparse-lp))
         (tmp-values (sparse-vector-values tmp))
         (tmp-indices (sparse-vector-indices tmp)))
    (symbol-macrolet ((tmp-nz (sparse-vector-nz tmp)))
      (dotimes (i m)
        (let ((coef (aref c (aref basics i))))
          (when (> (abs coef) +eps+)
            (setf (aref tmp-values tmp-nz) coef
                  (aref tmp-indices tmp-nz) i)
            (incf tmp-nz))))
      (sparse-solve-transposed! lude tmp)
      (let* ((tmp (tmat-times-vec! tmat tmp basic-flag))
             (tmp-values (sparse-vector-values tmp))
             (tmp-indices (sparse-vector-indices tmp)))
        (dotimes (j n)
          (setf (aref y-nonbasic j) (- (aref c (aref nonbasics j)))))
        (dotimes (k (sparse-vector-nz tmp))
          (incf (aref y-nonbasic (aref tmp-indices k)) (aref tmp-values k)))))
    sparse-lp))

(defun make-sparse-lp (a b c &key (add-slack t) (dictionary nil supplied-p))
  "Creates SPARSE-LP from a sparse matrix, which has the standard form: maximize
c'x subject to Ax <= b, x >= 0.

This function translates a given LP to an equality form Ax + w = b by adding
slack variables and changes A to (A E). If you want to give an equality form
directly, just disable ADD-SLACK.

You can set DICTIONARY to an arbitrary initial dictionary, but please note that
the consequence is undefined when it is rank-deficient."
  (declare (optimize (speed 3))
           (csc a)
           ((simple-array csc-float (*)) b c))
  (let* ((m (csc-m a))
         (n (if add-slack (csc-n a) (- (csc-n a) (csc-m a)))))
    (assert (= m (length b)))
    (when add-slack
      (setq a (add-slack! a)))
    ;; Add coefficients for basic variables
    (unless (= (length c) (+ m n))
      (assert (= n (length c)))
      (setq c (adjust-array c (the (mod #.array-dimension-limit) (+ n m))
                            :initial-element +zero+)))
    (let* ((x-basic (make-array m :element-type 'csc-float))
           (y-nonbasic (make-array n :element-type 'csc-float))
           (dictionary (or dictionary
                           (let ((basics (make-array m :element-type 'fixnum)))
                             (dotimes (i m)
                               (setf (aref basics i) (+ n i)))
                             (make-dictionary m n basics))))
           (basics (dictionary-basics dictionary))
           (a-transposed (csc-transpose a)))
      (unless supplied-p
        (dotimes (j n)
          (setf (aref y-nonbasic j) (- (aref c j)))))
      (dotimes (i m)
        (setf (aref x-basic i) (aref b i)))
      (let* ((lude (refactor a basics))
             (slp (%make-sparse-lp :m m :n n
                                   :mat a :tmat a-transposed
                                   :b b :c c
                                   :x-basic x-basic
                                   :y-nonbasic y-nonbasic
                                   :dictionary dictionary
                                   :lude lude)))
        (when supplied-p
          (correct-x-basic! lude x-basic)
          (correct-y-nonbasic! slp))
        slp))))

(declaim (ftype (function * (values csc-float &optional)) dot*))
(defun dot* (coefs x-basic basics)
  (declare (optimize (speed 3))
           ((simple-array csc-float (*)) coefs x-basic)
           ((simple-array fixnum (*)) basics))
  (let ((res +zero+))
    (declare (csc-float res))
    (dotimes (i (length x-basic))
      (incf res (* (aref coefs (aref basics i)) (aref x-basic i))))
    res))

(defconstant +initial-size+ 16)

(declaim ((simple-array csc-float (*)) *tmp-values*)
         ((simple-array fixnum (*)) *tmp-tags* *tmp-rows*)
         ((integer 0 #.most-positive-fixnum) *tmp-tag*))
(defparameter *tmp-values*
  (make-array +initial-size+ :element-type 'csc-float))
(defparameter *tmp-tags*
  (make-array +initial-size+ :element-type 'fixnum :initial-element 0))
(defparameter *tmp-tag* 1)
(defparameter *tmp-rows* (make-array +initial-size+ :element-type 'fixnum))

(defun tmat-times-vec! (tmat vec basic-flag &optional res)
  (declare (optimize (speed 3))
           (csc tmat)
           (sparse-vector vec)
           ((or null sparse-vector) res)
           ((simple-array fixnum (*)) basic-flag))
  (let ((m (csc-m tmat)))
    (extend-vectorf *tmp-values* m)
    (extend-vectorf *tmp-tags* m)
    (extend-vectorf *tmp-rows* m))
  (let ((tmp-values *tmp-values*)
        (tmp-tags *tmp-tags*)
        (tag *tmp-tag*)
        (tmp-rows *tmp-rows*)
        (vector-indices (sparse-vector-indices vec))
        (vector-values (sparse-vector-values vec))
        (tmat-values (csc-values tmat))
        (tmat-colstarts (csc-colstarts tmat))
        (tmat-rows (csc-rows tmat))
        (end 0))
    (declare ((mod #.array-dimension-limit)))
    (dotimes (k1 (sparse-vector-nz vec))
      (let ((col (aref vector-indices k1)))
        (loop for k2 from (aref tmat-colstarts col) below (aref tmat-colstarts (+ col 1))
              for row = (aref tmat-rows k2)
              when (< (aref basic-flag row) 0)
              do (unless (eql tag (aref tmp-tags row))
                   (setf (aref tmp-values row) +zero+
                         (aref tmp-tags row) tag
                         (aref tmp-rows end) row
                         end (+ end 1)))
                 (incf (aref tmp-values row)
                       (* (aref vector-values k1) (aref tmat-values k2))))))
    (let* ((res (or res (make-sparse-vector end)))
           (res-values (sparse-vector-values res))
           (res-indices (sparse-vector-indices res))
           (nz 0))
      (declare ((simple-array csc-float (*)) res-values)
               ((simple-array fixnum (*)) res-indices)
               ((mod #.array-dimension-limit) nz))
      (extend-vectorf res-values end)
      (extend-vectorf res-indices end)
      (dotimes (k end)
        (let ((row (aref tmp-rows k)))
          (when (> (abs (aref tmp-values row)) +eps+)
            (setf (aref res-values nz) (aref tmp-values row)
                  (aref res-indices nz) (lognot (aref basic-flag row))
                  nz (+ nz 1)))))
      (setf (sparse-vector-values res) res-values
            (sparse-vector-indices res) res-indices
            (sparse-vector-nz res) nz)
      (incf *tmp-tag*)
      res)))

(defun slp-restore (sparse-lp)
  "Restores the current solution of LP and returns five values: objective value,
primal solution, dual solution, values of primal slack variables, and values of
dual slack variables. (Note that they are not necessarily feasible solutions if
the current dictionary is not feasible.)"
  (declare (optimize (speed 3)))
  (let* ((m (slp-m sparse-lp))
         (n (slp-n sparse-lp))
         (c (slp-c sparse-lp))
         (x-basic (slp-x-basic sparse-lp))
         (y-nonbasic (slp-y-nonbasic sparse-lp))
         (dictionary (slp-dictionary sparse-lp))
         (basics (dictionary-basics dictionary))
         (nonbasics (dictionary-nonbasics dictionary))
         (x (make-array (+ n m) :element-type 'csc-float :initial-element +zero+))
         (y (make-array (+ n m) :element-type 'csc-float :initial-element +zero+)))
    (dotimes (i m)
      (setf (aref x (aref basics i)) (aref x-basic i)))
    (dotimes (i n)
      (setf (aref y (aref nonbasics i)) (aref y-nonbasic i)))
    (values (dot* c x-basic basics)
            (subseq x 0 n)
            (subseq y n)
            (subseq x n)
            (subseq y 0 n))))
