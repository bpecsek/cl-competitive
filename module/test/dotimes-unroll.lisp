(defpackage :cp/test/dotimes-unroll
  (:use :cl :fiveam :cp/dotimes-unroll)
  (:import-from :cp/test/base #:base-suite))
(in-package :cp/test/dotimes-unroll)
(in-suite base-suite)

(defun iter3 (sup)
  (let (stack)
    (dotimes-unroll (x sup 3)
      (push x stack))
    (nreverse stack)))

(test dotimes-unroll
  (let (stack)
    (dotimes-unroll (x 8 5) (push x stack))
    (is (equal '(7 6 5 4 3 2 1 0) stack)))
  (let (stack)
    (dotimes-unroll (x 8 4) (push x stack))
    (is (equal '(7 6 5 4 3 2 1 0) stack)))
  (let (stack)
    (dotimes-unroll (x 8 3) (push x stack))
    (is (equal '(7 6 5 4 3 2 1 0) stack)))
  (let (stack)
    (dotimes-unroll (x 8 2) (push x stack))
    (is (equal '(7 6 5 4 3 2 1 0) stack)))
  (let (stack)
    (dotimes-unroll (x 8 1) (push x stack))
    (is (equal '(7 6 5 4 3 2 1 0) stack)))
  (let (stack)
    (dotimes-unroll (x 8 9) (push x stack))
    (is (equal '(7 6 5 4 3 2 1 0) stack)))
  (let (stack)
    (dotimes-unroll-all (x 8) (push x stack))
    (is (equal '(7 6 5 4 3 2 1 0) stack)))

  (is (null (iter3 0)))
  (is (equal '(0) (iter3 1)))
  (is (equal '(0 1 2) (iter3 3)))
  (is (equal '(0 1 2 3) (iter3 4)))
  (is (equal '(0 1 2 3 4 5 6) (iter3 7)))

  ;; result
  (is (null (dotimes-unroll (x 8 3))))
  (is (= -1 (dotimes-unroll (x 8 3 -1)))))
