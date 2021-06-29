(defpackage :cp/test/lu-decomposition
  (:use :cl :fiveam :cp/lu-decomposition :cp/csc :cp/gemm :cp/test/nearly-equal
        :cp/lp-test-tool)
  (:import-from :cp/test/base #:base-suite)
  (:import-from :cp/csc #:csc-float))
(in-package :cp/test/lu-decomposition)
(in-suite base-suite)

(test lu-factor/hand
  (is (zerop (lud-rank (lu-factor (make-csc 0 0 0
                                            (make-array 0 :element-type 'fixnum)
                                            (make-array 0 :element-type 'fixnum)
                                            (make-array 0 :element-type 'csc-float))
                                  #()))))
  ;; smaller cell than epsnum
  (is (= 4 (lud-rank (lu-factor (make-csc-from-array #2a((0d0 0d0 4d0 0d0 -2d0)
                                                         (0d0 1d0 0d0 1d0 0d0)
                                                         (0d0 0d0 -1d0 0d0 -2d0)
                                                         (1d-10 -1d0 0d0 0d0 -6d0)
                                                         (1d-10 0d0 1d0 0d0 4d0)))
                                #(0 1 2 3 4)))))
  (is (= 5 (lud-rank (lu-factor (make-csc-from-array #2a((0d0 0d0 4d0 0d0 -2d0)
                                                         (0d0 1d0 0d0 1d0 0d0)
                                                         (0d0 0d0 -1d0 0d0 -2d0)
                                                         (1d-5 -1d0 0d0 0d0 -6d0)
                                                         (1d-5 0d0 1d0 0d0 4d0)))
                                #(0 1 2 3 4))))))

(defun make-dense-lu (lud)
  (let* ((rowperm (lud-rowperm lud))
         (colperm (lud-colperm lud))
         (l (csc-to-array (lud-lower lud) rowperm nil))
         (u (csc-to-array (lud-upper lud) nil colperm))
         (diagu (lud-diagu lud))
         (m (lud-m lud)))
    (dotimes (i m)
      (setf (aref u i (aref colperm i)) (aref diagu i)
            (aref l (aref rowperm i) i) 1d0))
    (values l u)))

(test lu-factor/random
  (let ((*test-dribble* nil)
        (*random-state* (sb-ext:seed-random-state 0)))
    (dolist (m '(1 3 5 10))
      (dolist (rate '(0.0 0.2 0.4 0.6 0.8 1.0))
        (dotimes (_ 100)
          (let ((mat (make-array (list m m) :element-type 'csc-float))
                (basis (make-array m :element-type 'fixnum)))
            (declare ((simple-array csc-float (* *)) mat))
            (dotimes (i m)
              (setf (aref basis i) i))
            (dotimes (i m)
              (dotimes (j m)
                (when (< (random 1d0) rate)
                  (setf (aref mat i j) (fround (- (random 10d0) 5d0))))))
            (let* ((csc (make-csc-from-array mat))
                   (lud (lu-factor csc basis)))
              (multiple-value-bind (l u) (make-dense-lu lud)
                (let ((restored (gemm l u)))
                  (declare ((simple-array csc-float (* *)) restored))
                  (dotimes (i m)
                    (dotimes (j m)
                      (is (nearly= 1d-8 (aref mat i j) (aref restored i j)))))))
              (when (= (lud-rank lud) m)
                (let ((y (make-array m :element-type 'csc-float)))
                  (dotimes (i m)
                    (setf (aref y i) (fround (- (random 10d0) 5d0))))
                  (let ((sol (dense-solve! lud (copy-seq y))))
                    (dotimes (i m)
                      (is (nearly= 1d-8
                                   (aref y i)
                                   (loop for j below m
                                         sum (* (aref mat i j) (aref sol j))))))))))))))))

(defparameter *mat* (copy #2a((2d0 0d0 4d0 0d0 -2d0 1d0)
                              (3d0 1d0 0d0 1d0 0d0 2d0)
                              (-1d0 0d0 -1d0 0d0 -2d0 3d0)
                              (0d0 -1d0 0d0 0d0 -6d0 0d0)
                              (0d0 0d0 1d0 0d0 4d0 0d0))))

(test sparse-solve
  ;; Vanderbei. Linear Programming. 5th edition. p. 136.
  (let* ((lude (make-lud-eta (lu-factor (make-csc-from-array *mat*) #(0 1 2 3 4))))
         (sol1 (sparse-solve! lude (make-sparse-vector-from #(7d0 -2d0 0d0 3d0 0d0)))))
    (add-eta! lude 2 sol1)
    (dotimes (_ 5)
      (is (nearly-equal 1d-8
                        '(-1d0 0d0 2d0 1d0 -0.5d0)
                        (coerce (to-dense-vector sol1) 'list))))
    (let ((sol2 (sparse-solve! lude (make-sparse-vector-from #(5d0 0d0 0d0 0d0 -1d0)))))
      (dotimes (_ 5)
        (is (nearly-equal 1d-8
                          '(0.5d0 3d0 0.5d0 -3.5d0 -0.25d0)
                          (coerce (to-dense-vector sol2) 'list)))))))
