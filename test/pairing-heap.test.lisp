(eval-when (:compile-toplevel :load-toplevel :execute)
  (load "test-util")
  (load "../pairing-heap.lisp"))

(use-package :test-util)

(with-test (:name pairing-heap)
  (let (heap)
    (dolist (e (list 10 -1 2  -5 0 0 -1 11))
      (pheap-push e heap #'<))
    (assert (= -5 (pheap-pop heap #'<)))
    (assert (= -1 (pheap-pop heap #'<)))
    (assert (= -1 (pheap-pop heap #'<)))
    (assert (= 0 (pheap-pop heap #'<)))
    (assert (= 0 (pheap-pop heap #'<)))
    (assert (= 2 (pheap-pop heap #'<)))
    (assert (= 10 (pheap-pop heap #'<)))
    (assert (= 11 (pheap-pop heap #'<)))
    (assert (null heap))))

(defun bench (sample)
  (declare (optimize (speed 3))
           ((unsigned-byte 32) sample))
  (let ((vector (make-array 10000 :element-type '(unsigned-byte 32)))
        (state (sb-ext:seed-random-state 0))
        heap)
    (dotimes (i (length vector))
      (setf (aref vector i) (random 1000 state)))
    (gc :full t)
    (time (dotimes (_ sample)
            (sb-int:dovector (e vector)
              (pheap-push e heap #'<))
            (dotimes (i (length vector))
              (pheap-pop heap #'<))))))