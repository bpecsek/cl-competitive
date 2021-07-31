(defpackage :cp/sum-of-geometric-series
  (:use :cl)
  (:export #:geom-sum))
(in-package :cp/sum-of-geometric-series)

(declaim (inline geom-sum))
(defun geom-sum (base exp op* op+ iden* iden+)
  "Returns I + BASE + BASE^2 + ... + BASE^(EXP-1)."
  (declare (unsigned-byte exp))
  (let ((base00 base)
        (base10 iden*)
        (res00 iden*)
        (res10 iden+))
    (loop until (zerop exp)
          when (oddp exp)
          do (setq res00 (funcall op* res00 base00)
                   res10 (funcall op+ (funcall op* res10 base00) base10))
          do (setq exp (ash exp -1)
                   base10 (funcall op+ (funcall op* base10 base00) base10)
                   base00 (funcall op* base00 base00)))
    res10))
