(defpackage :cp/alphametics
  (:use :cl :cp/map-permutations)
  (:export #:solve-alphametics))
(in-package :cp/alphametics)

(defun solve-alphametics (s1 s2 s3 &optional (test #'eql) (base 10))
  (declare (optimize (speed 3))
           (vector s1 s2 s3)
           ((integer 0 #.most-positive-fixnum) base))
  (let* ((indexer (make-hash-table :test test))
         (end 0))
    (declare ((mod #.array-dimension-limit) end))
    (labels ((index (s)
               (loop for c across s
                     unless (gethash c indexer)
                     do (setf (gethash c indexer) end)
                        (incf end)))
             (compress (s)
               (let ((res (make-array (length s) :element-type 'fixnum)))
                 (dotimes (i (length s))
                   (setf (aref res i)
                         (gethash (aref s i) indexer)))
                 res)))
      (index s1)
      (index s2)
      (index s3)
      (when (> end base)
        (return-from solve-alphametics))
      (let ((s1 (compress s1))
            (s2 (compress s2))
            (s3 (compress s3))
            (iota (make-array base :element-type '(integer 0 #.most-positive-fixnum))))
        (dotimes (i base)
          (setf (aref iota i) i))
        (do-permutations! (table iota)
          (declare ((simple-array (integer 0 #.most-positive-fixnum) (*)) iota))
          (labels ((numerize (s)
                     (let ((res 0))
                       (declare (unsigned-byte res))
                       (dotimes (i (length s))
                         (setq res (+ (* res base)
                                      (aref table (aref s i)))))
                       res))
                   (valid-p (s)
                     (/= 0 (aref table (aref s 0)))))
            (when (and (valid-p s1)
                       (valid-p s2)
                       (valid-p s3))
              (let ((n1 (numerize s1))
                    (n2 (numerize s2))
                    (n3 (numerize s3)))
                (when (= (+ n1 n2) n3)
                  (return-from solve-alphametics
                    (values n1 n2 n3)))))))))))