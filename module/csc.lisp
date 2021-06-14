(defpackage :cp/csc
  (:use :cl)
  (:export #:csc #:make-csc #:csc-to-array #:make-csc-from-array #:make-csc-from-coo)
  (:documentation "Provides compressed sparse column representation of sparse
matrix."))
(in-package :cp/csc)

(deftype csc-float () 'double-float)
(defconstant +zero+ (coerce 0 'csc-float))

(defstruct (csc (:constructor make-csc (m n colstarts rows values))
                (:copier nil)
                (:predicate nil))
  (m nil :type (mod #.array-dimension-limit))
  (n nil :type (mod #.array-dimension-limit))
  (colstarts nil :type (simple-array fixnum (*)))
  (rows nil :type (simple-array fixnum (*)))
  (values nil :type (simple-array csc-float (*))))

(defun csc-to-array (csc)
  (declare (optimize (speed 3)))
  (let* ((m (csc-m csc))
         (n (csc-n csc))
         (res (make-array (list m n) :element-type 'csc-float :initial-element +zero+))
         (colstarts (csc-colstarts csc))
         (rows (csc-rows csc))
         (values (csc-values csc)))
    (dotimes (col n)
      (loop for i from (aref colstarts col) below (aref colstarts (+ col 1))
            for row = (aref rows i)
            for value = (aref values i)
            do (setf (aref res row col) value)))
    res))

(defun make-csc-from-array (array)
  "Makes CSC from a 2-dimensional array."
  (declare (optimize (speed 3))
           ((array * (* *)) array))
  (destructuring-bind (m n) (array-dimensions array)
    (declare ((mod #.array-dimension-limit) m n))
    (let* ((colstarts (make-array (+ n 1) :element-type 'fixnum))
           (length (count +zero+ (sb-ext:array-storage-vector array) :test-not #'=))
           (rows (make-array length :element-type 'fixnum))
           (values (make-array length :element-type 'csc-float))
           (end 0))
      (declare ((mod #.array-dimension-limit) end))
      (dotimes (col n)
        (setf (aref colstarts col) end)
        (dotimes (row m)
          (let ((value (aref array row col)))
            (unless (zerop value)
              (setf (aref rows end) row
                    (aref values end) value)
              (incf end)))))
      (setf (aref colstarts n) end)
      (make-csc m n colstarts rows values))))

(declaim (inline make-csc-from-coo))
(defun make-csc-from-coo (m n rows cols values)
  "Makes CSC from a coordinalte list expression of a sparse matrix.

Note:
- This function uses the element closest to the end if duplicate (row, col) exist.
- The returned CSC contains zero when VALUES contains it."
  (declare (inline sort)
           (vector rows cols values))
  (assert (= (length rows) (length cols) (length values)))
  (let* ((indices (let ((tmp (make-array (length rows) :element-type 'fixnum)))
                    (dotimes (i (length rows))
                      (setf (aref tmp i) i))
                    (stable-sort tmp (lambda (i1 i2)
                                       (if (= (aref cols i1) (aref cols i2))
                                           (< (aref rows i1) (aref rows i2))
                                           (< (aref cols i1) (aref cols i2)))))))
         (length 0))
    (dotimes (i* (length indices))
      (let ((i (aref indices i*)))
        (if (and (> i* 0)
                 (let ((prev-i (aref indices (- i* 1))))
                   (and (= (aref rows i) (aref rows prev-i))
                        (= (aref cols i) (aref cols prev-i)))))
            (setf (aref indices (- length 1)) i)
            (setf (aref indices length) i
                  length (+ length 1)))))
    (let ((colstarts (make-array (+ n 1) :element-type 'fixnum))
          (csc-rows (make-array length :element-type 'fixnum))
          (csc-values (make-array length :element-type 'csc-float))
          (end 0)
          (prev-col -1))
      (declare ((mod #.array-dimension-limit) end)
               ((integer -1 (#.array-dimension-limit)) prev-col))
      (dotimes (i* length)
        (let* ((i (aref indices i*))
               (row (aref rows i))
               (col (aref cols i))
               (value (aref values i)))
          (loop for j from col above prev-col
                do (setf (aref colstarts j) end))
          (setf (aref csc-rows end) row
                (aref csc-values end) value)
          (incf end)
          (setq prev-col col)))
      (loop for j from n above prev-col
            do (setf (aref colstarts j) end))
      (make-csc m n colstarts csc-rows csc-values))))
