(eval-when (:compile-toplevel :load-toplevel :execute)
  (load "test-util")
  (load "../ext-gcd.lisp"))

(use-package :test-util)

(with-test (:name mod-log)
  (dotimes (i 100)
    (let ((a (- (random 20) 10))
          (b (- (random 20) 10)))
      (multiple-value-bind (x y) (ext-gcd a b)
        (assert (= (+ (* a x) (* b y)) (gcd a b))))))
  (assert (= 8 (mod-log 6 4 44)))
  (assert (= 8 (mod-log -38 -40 44)))
  (assert (null (mod-log 6 2 44)))
  (assert (= 2 (mod-log 8 4 12)))
  (assert (= 4 (mod-log 3 13 17)))
  (assert (= 1 (mod-log 12 0 4)))
  (assert (= 2 (mod-log 12 0 8)))
  (assert (null (mod-log 12 1 8)))
  (assert (= 1 (mod-log 0 0 100))))

(with-test (:name mod-inverse)
  (dotimes (i 1000)
    (let ((a (random 100))
          (m (+ 2 (random 100))))
      (assert (or (/= 1 (gcd a m))
                  (= 1 (mod (* a (mod-inverse a m)) m)))))))

(with-test (:name solve-bezout)
  (assert (= (calc-min-factor 8 3) -2))
  (assert (= (calc-min-factor -8 3) 3))
  (assert (= (calc-min-factor 8 -3) 2))
  (assert (= (calc-min-factor -8 -3) -3))
  (assert (= (calc-max-factor 8 3) -3))
  (assert (= (calc-max-factor -8 3) 2))
  (assert (= (calc-max-factor 8 -3) 3))
  (assert (= (calc-max-factor -8 -3) -2)))
