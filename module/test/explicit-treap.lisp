(defpackage :cp/test/explicit-treap
  (:use :cl :fiveam :cp/explicit-treap)
  (:import-from :cp/test/base #:base-suite)
  (:import-from :cp/explicit-treap
                #:%treap-priority #:%treap-key #:%treap-left #:%treap-right
                #:%treap-accumulator #:%treap-value #:%make-treap #:op))
(in-package :cp/test/explicit-treap)
(in-suite base-suite)

(defun treap-priority (treap)
  (declare ((or null treap) treap))
  (if (null treap)
      0
      (%treap-priority treap)))

(defun treap-sane-p (treap)
  (or (null treap)
      (and (>= (%treap-priority treap)
               (treap-priority (%treap-left treap)))
           (>= (%treap-priority treap)
               (treap-priority (%treap-right treap)))
           (= (%treap-accumulator treap)
              (op (op (treap-accumulator (%treap-left treap))
                      (%treap-value treap))
                  (treap-accumulator (%treap-right treap))))
           (treap-sane-p (%treap-left treap))
           (treap-sane-p (%treap-right treap)))))

(defun copy-treap (treap)
  "For development. Recursively copies the whole TREAP."
  (declare ((or null treap) treap))
  (if (null treap)
      nil
      (%make-treap (%treap-key treap)
                   (%treap-priority treap)
                   (%treap-value treap)
                   :accumulator (%treap-accumulator treap)
                   :left (copy-treap (%treap-left treap))
                   :right (copy-treap (%treap-right treap)))))

(test explicit-treap-sanity
  (declare (notinline make-treap))
  (loop repeat 10
        do (assert (treap-sane-p (make-treap #(1 2 3 4 5 6 7 8 9 10))))
           (assert (treap-sane-p (make-treap #(1 2 3 4 5 6 7 8 9))))
           (assert (treap-sane-p (make-treap #(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17))))
           (assert (treap-sane-p (make-treap #(1 2 3 4))))
           (assert (treap-sane-p (make-treap #(1))))
           (assert (treap-sane-p nil))))

(test explicit-treap-bisection
  (declare (notinline treap-bisect-left treap-bisect-right treap-bisect-left-1 treap-bisect-right-1))
  (let ((treap (treap #'> '(50 . 3) '(20 . 1) '(40 . 4))))
    (assert (null (treap-find treap 0 :order #'>)))
    (assert (= 50 (treap-find treap 50 :order #'>)))
    (assert (= 40 (treap-find treap 40 :order #'>)))
    (assert (= 20 (treap-find treap 20 :order #'>)))
    (assert (null (treap-bisect-right-1 treap 51 :order #'>)))
    (assert (= 50 (treap-bisect-right-1 treap 50 :order #'>)))
    (assert (= 50 (treap-bisect-right-1 treap 49 :order #'>)))
    (assert (= 40 (treap-bisect-right-1 treap 40 :order #'>)))
    (assert (= 20 (treap-bisect-right-1 treap 0 :order #'>)))
    (assert (= 50 (treap-bisect-left treap 51 :order #'>)))
    (assert (= 50 (treap-bisect-left treap 50 :order #'>)))
    (assert (= 40 (treap-bisect-left treap 49 :order #'>)))
    (assert (= 40 (treap-bisect-left treap 40 :order #'>)))
    (assert (null (treap-bisect-left treap 0 :order #'>)))
    (assert (= 50 (treap-bisect-right treap 51 :order #'>)))
    (assert (= 40 (treap-bisect-right treap 50 :order #'>)))
    (assert (= 20 (treap-bisect-right treap 40 :order #'>)))
    (assert (null (treap-bisect-right treap 20 :order #'>)))
    (assert (null (treap-bisect-left-1 treap 50 :order #'>)))
    (assert (= 50 (treap-bisect-left-1 treap 49 :order #'>)))
    (assert (= 50 (treap-bisect-left-1 treap 40 :order #'>)))
    (assert (= 40 (treap-bisect-left-1 treap 39 :order #'>)))
    (assert (= 20 (treap-bisect-left-1 treap 19 :order #'>)))
    (assert (= 20 (treap-bisect-left-1 treap -10000 :order #'>)))))
