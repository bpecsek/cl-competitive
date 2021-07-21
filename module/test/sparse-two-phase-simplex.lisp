(defpackage :cp/test/sparse-two-phase-simplex
  (:use :cl :fiveam :cp/sparse-two-phase-simplex :cp/sparse-simplex-common
        :cp/test/nearly-equal :cp/csc :cp/lud :cp/lp-test-tool :cp/shuffle)
  (:import-from :cp/test/base #:base-suite)
  (:import-from :cp/sparse-two-phase-simplex #:tmat-times-vec!))
(in-package :cp/test/sparse-two-phase-simplex)
(in-suite base-suite)

(test slp-primal!
  ;; trival lp
  (let* ((b (make-array 0 :element-type 'double-float))
         (c (make-array 0 :element-type 'double-float))
         (lp (make-sparse-lp (make-csc-from-array #2a()) b c)))
    (is (eql :optimal (slp-primal! lp)))
    (multiple-value-bind (obj prim dual prim-slack dual-slack) (slp-restore lp)
      (is (zerop obj))
      (is (equalp #() prim))
      (is (equalp #() dual))
      (is (equalp #() prim-slack))
      (is (equalp #() dual-slack))))
  ;; zero lp
  (dolist (dim '((2 . 3) (10 . 10) (1 . 1) (10 . 3) (3 . 10)))
    (destructuring-bind (m . n) dim
      (let* ((mat (make-array (list m n) :element-type 'double-float :initial-element 0d0))
             (b (make-array m :element-type 'double-float :initial-element 0d0))
             (c+ (make-array n :element-type 'double-float :initial-element 1d0))
             (c- (make-array n :element-type 'double-float :initial-element -1d0)))
        (dotimes (i m)
          (setf (aref b i) (float (random 20) 1d0)))
        (let* ((lp (make-sparse-lp (make-csc-from-array mat) b c+)))
          (is (eql :unbounded (slp-primal! lp))))
        (let* ((lp (make-sparse-lp (make-csc-from-array mat) b c-)))
          (is (eql :optimal (slp-primal! lp))))))))

(defun check (mat b c mat-dual b-dual c-dual lp)
  (multiple-value-bind (obj prim dual prim-slack dual-slack)
      (slp-restore lp)
    ;; check primal
    (let ((lhs (csc-gemv mat prim))
          (obj2 (loop for x across prim
                      for coef across c
                      sum (* x coef))))
      (is (nearly= 1d-8 obj obj2))
      (dotimes (i (length prim-slack))
        (incf (aref lhs i) (aref prim-slack i)))
      (is (nearly-equalp 1d-8 lhs b))
      (is (loop for x across prim
                always (>= x -1d-8)))
      (is (loop for x across prim-slack
                always (>= x -1d-8))))
    ;; check dual
    (let ((lhs (csc-gemv mat-dual dual))
          (obj2 (loop for y across dual
                      for coef across c-dual
                      sum (* y coef))))
      (dotimes (i (length dual-slack))
        (incf (aref lhs i) (aref dual-slack i)))
      (is (nearly= 1d-8 obj (- obj2)))
      (is (nearly-equalp 1d-8 lhs b-dual))
      (is (loop for x across dual
                always (>= x -1d-8)))
      (is (loop for x across dual-slack
                always (>= x -1d-8))))))

(test sparse-one-phase-simplex/random
  (let ((*random-state* (sb-ext:seed-random-state 0))
        (*test-dribble* nil))
    (labels
        ((proc ()
           (dolist (dim '((2 . 3) (10 . 10) (1 . 1) (10 . 3) (3 . 10)))
             (dolist (rate '(0.1 0.4 0.7 0.9))
               (dotimes (_ 200)
                 (let* ((m (car dim))
                        (n (cdr dim))
                        (mat (make-array (list m n)
                                         :element-type 'double-float
                                         :initial-element 0d0))
                        (mat-dual (make-array (list n m)
                                              :element-type 'double-float
                                              :initial-element 0d0))
                        (b (make-array m :element-type 'double-float :initial-element 0d0))
                        (c (make-array n :element-type 'double-float :initial-element 0d0)))
                   (dotimes (i m)
                     (dotimes (j n)
                       (when (< (random 1d0) rate)
                         (let ((val (float (- (random 20) 10) 1d0)))
                           (setf (aref mat i j) val
                                 (aref mat-dual j i) (- val))))))
                   (dotimes (i m)
                     (setf (aref b i) (float (random 20) 1d0)))
                   (dotimes (j n)
                     (setf (aref c j) (float (- (random 20) 10) 1d0)))
                   (let* ((b- (map '(simple-array double-float (*)) #'- b))
                          (c- (map '(simple-array double-float (*)) #'- c))
                          (csc (make-csc-from-array mat))
                          (csc-dual (make-csc-from-array mat-dual))
                          (lp (make-sparse-lp csc b c))
                          (lp-dual (make-sparse-lp csc-dual c- b-))
                          (result1 (slp-primal! lp))
                          (result2 (slp-dual! lp-dual)))
                     (is (or (and (eql result1 :optimal) (eql result2 :optimal))
                             (and (eql result1 :unbounded) (eql result2 :infeasible))))
                     ;; check sparse-primal!
                     (when (eql result1 :optimal)
                       (check csc b c csc-dual c- b- lp))
                     ;; check sparse-dual!
                     (when (eql result2 :optimal)
                       (check csc-dual c- b- csc b c lp-dual)))))))))
      (let ((*refactor-threshold* 1))
        (proc))
      (let ((*refactor-threshold* 200)
            (*refactor-by-time* nil))
        (proc)))))

(defun choose (vector k)
  (let ((vector (copy-seq vector)))
    (shuffle! vector)
    (subseq vector 0 k)))

(test sparse-two-phase-simplex/random
  (let ((*random-state* (sb-ext:seed-random-state 0))
        (*test-dribble* nil))
    (labels
        ((proc ()
           (dolist (dim '((2 . 3) (10 . 10) (1 . 1) (10 . 3) (3 . 10)))
             (dolist (rate '(0.1 0.5 0.9))
               (dotimes (_ 200)
                 (let* ((m (car dim))
                        (n (cdr dim))
                        (mat (make-array (list m n)
                                         :element-type 'double-float
                                         :initial-element 0d0))
                        (mat-dual (make-array (list n m)
                                              :element-type 'double-float
                                              :initial-element 0d0))
                        (b (make-array m :element-type 'double-float :initial-element 0d0))
                        (c (make-array n :element-type 'double-float :initial-element 0d0))
                        (cols (make-array (+ n m) :element-type 'fixnum)))
                   (dotimes (i (length cols))
                     (setf (aref cols i) i))
                   (dotimes (i m)
                     (dotimes (j n)
                       (when (< (random 1d0) rate)
                         (let ((val (float (- (random 20) 10) 1d0)))
                           (setf (aref mat i j) val
                                 (aref mat-dual j i) (- val))))))
                   (dotimes (i m)
                     (setf (aref b i) (float (- (random 20) 10) 1d0)))
                   (dotimes (j n)
                     (setf (aref c j) (float (- (random 20) 10) 1d0)))
                   (let* ((basics (choose cols m))
                          (dictionary (make-dictionary m n basics))
                          (b- (map '(simple-array double-float (*)) #'- b))
                          (c- (map '(simple-array double-float (*)) #'- c))
                          (csc (make-csc-from-array mat))
                          (csc-dual (make-csc-from-array mat-dual))
                          (lp (let ((lp (make-sparse-lp csc b c :dictionary dictionary)))
                                (if (= m (lud-rank (lud-eta-lud (slp-lude lp))))
                                    lp
                                    (make-sparse-lp csc b c :add-slack nil))))
                          (lp-dual (make-sparse-lp csc-dual c- b-)))
                     (let ((result1 (slp-dual-primal! lp))
                           (result2 (slp-dual-primal! lp-dual)))
                       (is (or (and (eql result1 :optimal) (eql result2 :optimal))
                               (and (eql result1 :unbounded) (eql result2 :infeasible))
                               (and (eql result1 :infeasible) (eql result2 :unbounded))
                               (and (eql result1 :infeasible) (eql result2 :infeasible))))
                       ;; check sparse-primal!
                       (when (eql result1 :optimal)
                         (check csc b c csc-dual c- b- lp))
                       ;; check sparse-dual!
                       (when (eql result2 :optimal)
                         (check csc-dual c- b- csc b c lp-dual))))))))))
      (let ((*refactor-threshold* 1))
        (proc))
      (let ((*refactor-threshold* 200)
            (*refactor-by-time* nil))
        (proc)))))

(defun test* ()
  (let ((m 5)
        (n 5)
        (rate 1d0)
        (count 0))
    (dotimes (_ 10000)
      (let ((coo (make-coo m n))
            (coo-dual (make-coo n m))
            (b (make-array m :element-type 'double-float :initial-element 0d0))
            (c (make-array n :element-type 'double-float :initial-element 0d0))
            (cols (make-array (+ n m) :element-type 'fixnum)))
        (dotimes (i (length cols))
          (setf (aref cols i) i))
        (dotimes (i m)
          (dotimes (j n)
            (when (< (random 1d0) rate)
              (let ((val (float (- (random 20) 10) 1d0)))
                (coo-insert! coo i j val)
                (coo-insert! coo-dual j i (- val))))))
        (dotimes (i m)
          (setf (aref b i) (float (- (random 20) 10) 1d0)))
        (dotimes (j n)
          (setf (aref c j) (float (- (random 20) 10) 1d0)))
        (let* ((b- (map '(simple-array double-float (*)) #'- b))
               (c- (map '(simple-array double-float (*)) #'- c))
               (basics (choose cols m))
               (dict (make-dictionary m n (copy-seq basics)))
               (csc (make-csc-from-coo coo))
               (csc-dual (make-csc-from-coo coo-dual))
               (lp (make-sparse-lp csc b c :dictionary dict))
               (rank (lud-rank (lud-eta-lud (slp-lude lp)))))
          (when (= m rank)
            (let ((result (slp-dual-primal! lp)))
              ;; (print result)
              (when (eql result :optimal)
                (incf count)
                (multiple-value-bind (obj prim dual prim-slack dual-slack)
                    (slp-restore lp)
                  ;; check primal
                  (let ((lhs (csc-gemv csc prim))
                        (obj2 (loop for x across prim
                                    for coef across c
                                    sum (* x coef))))
                    (dotimes (i (length prim-slack))
                      (incf (aref lhs i) (aref prim-slack i)))
                    (assert (nearly= 1d-5 obj obj2))
                    (assert (nearly-equalp 1d-8 lhs b))
                    (assert (loop for x across prim
                                  always (>= x -1d-5)))
                    (assert (loop for x across prim-slack
                                  always (>= x -1d-5))))
                  (let ((lhs (csc-gemv csc-dual dual))
                        (obj2 (loop for y across dual
                                    for coef across b-
                                    sum (* y coef))))
                    (dotimes (i (length dual-slack))
                      (incf (aref lhs i) (aref dual-slack i)))
                    (assert (nearly= 1d-8 obj (- obj2)))
                    (assert (nearly-equalp 1d-8 lhs c-))
                    (assert (loop for x across dual
                                  always (>= x -1d-8)))
                    (assert (loop for x across dual-slack
                                  always (>= x -1d-8)))))))))))
    count))
