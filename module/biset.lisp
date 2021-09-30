(defpackage :cp/biset
  (:use :cl :cp/bmi)
  (:export #:biset #:biset-set1 #:biset-set0 #:biset-set #:biset-ref
           #:biset-count1 #:biset-count #:make-biset #:%biset-total
           #:biset-select #:biset-find>= #:biset-find> #:biset-find<= #:biset-find<)
  (:import-from #:sb-vm #:n-word-bits #:unsigned-word-find-first-bit)
  (:import-from #:sb-sys #:%primitive))
(in-package :cp/biset)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (assert (= n-word-bits 64)))

(deftype uint () '(unsigned-byte 31))

(defstruct (biset (:constructor %make-biset)
                  (:conc-name %biset-))
  (n nil :type uint)
  (nw nil :type uint)
  (total 0 :type uint)
  (tree nil :type (simple-array uint (*)))
  (bits nil :type simple-bit-vector))

(declaim (inline biset-set1))
(defun biset-set1 (biset index)
  "bit-vector interpretation: Sets the bit at INDEX.
ordered set interpretation: Inserts INDEX to BISET."
  (declare (uint index))
  (let ((bits (%biset-bits biset))
        (tree (%biset-tree biset))
        (nw (%biset-nw biset)))
    (when (zerop (aref bits index))
      (setf (aref bits index) 1)
      (incf (%biset-total biset))
      (do ((bi (floor index n-word-bits) (logior bi (+ bi 1))))
          ((>= bi nw))
        (declare (uint bi))
        (incf (aref tree bi))))))

(declaim (inline biset-set0))
(defun biset-set0 (biset index)
  "bit-vector interpretation: Unsets the bit at INDEX.
ordered set interpretation: Deletes INDEX from BISET."
  (declare (optimize (speed 3))
           (uint index))
  (let ((bits (%biset-bits biset))
        (tree (%biset-tree biset))
        (nw (%biset-nw biset)))
    (when (= 1 (aref bits index))
      (setf (aref bits index) 0)
      (decf (%biset-total biset))
      (do ((bi (floor index n-word-bits) (logior bi (+ bi 1))))
          ((>= bi nw))
        (declare (uint bi))
        (decf (aref tree bi))))))

(declaim (inline biset-ref))
(defun biset-ref (biset index)
  (aref (%biset-bits biset) index))

(declaim (inline (setf biset-ref)))
(defun (setf biset-ref) (new-value biset index)
  (if (zerop new-value)
      (biset-set0 biset index)
      (biset-set1 biset index))
  new-value)

(declaim (inline biset-count1)
         (ftype (function * (values uint &optional)) biset-count1))
(defun biset-count1 (biset end)
  "bit-vector interpretation: Returns the number of 1's in the interval [0,
END).
ordered set interpretation: Returns the leftmost index at which END can be
inserted with keeping the order. (or equivalent to lower_bound() of C++)."
  (declare (optimize (speed 3) (safety 0))
           (uint end))
  (let ((bits (%biset-bits biset))
        (tree (%biset-tree biset)))
    (multiple-value-bind (bend rem) (floor end n-word-bits)
      (let ((res (logcount (ldb (byte rem 0) (sb-kernel:%vector-raw-bits bits bend)))))
        (declare (uint res))
        (do ((bi bend (logand bi (- bi 1))))
            ((<= bi 0))
          (declare (uint bi))
          (incf res (aref tree (- bi 1))))
        res))))

(declaim (inline biset-count)
         (ftype (function * (values uint &optional)) biset-count))
(defun biset-count (biset end bit)
  (declare (bit bit)
           (uint end))
  (let ((one (biset-count1 biset end)))
    (if (zerop bit)
        (- end one)
        one)))

(defun %build-tree! (biset)
  (declare (optimize (speed 3) (safety 0)))
  (let ((nw (%biset-nw biset))
        (tree (%biset-tree biset))
        (bits (%biset-bits biset)))
    (dotimes (i nw)
      (setf (aref tree i) (logcount (sb-kernel:%vector-raw-bits bits i))))
    (dotimes (i nw)
      (let ((dest-i (logior i (+ i 1))))
        (when (< dest-i nw)
          (incf (aref tree dest-i) (aref tree i)))))))

(declaim (inline make-biset))
(defun make-biset (length &key initial-contents)
  (declare (optimize (speed 3))
           (uint length)
           ((or null vector) initial-contents))
  (assert (or (null initial-contents) (= length (length initial-contents))))
  (let* ((nw (+ 1 (floor length n-word-bits)))
         (tree (make-array nw :element-type 'uint :initial-element 0))
         (bits (make-array (* nw n-word-bits) :element-type 'bit :initial-element 0))
         (res (%make-biset :n length :nw nw :tree tree :bits bits)))
    (when initial-contents
      (replace bits initial-contents)
      (setf (%biset-total res) (count 1 bits))
      (%build-tree! res))
    res))

;; not tested
(declaim (inline %make-biset-from))
(defun %make-biset-from (bits)
  (declare (optimize (speed 3))
           (simple-bit-vector bits))
  (let* ((length (length bits))
         (nw (ceiling length n-word-bits))
         (tree (make-array nw :element-type 'uint :initial-element 0))
         (res (%make-biset :n length :nw nw :tree tree :bits bits)))
    (setf (%biset-total res) (count 1 bits))
    (%build-tree! res)
    res))

(declaim (ftype (function * (values uint &optional)) biset-select))
(defun biset-select (biset rank)
  "bit-vector interpretation: Returns the position of the RANK-th 1.
ordered set interpretation: Returns the (0-based) RANK-th element."
  (declare (optimize (speed 3))
           (biset biset)
           (uint rank))
  (assert (< rank (%biset-total biset)))
  (let ((tree (%biset-tree biset))
        (bits (%biset-bits biset))
        (nw (%biset-nw biset))
        (index+1 0))
    (declare (uint index+1))
    (do ((step (ash 1 (- (integer-length nw) 1)) (ash step -1)))
        ((zerop step) index+1)
      (declare (uint step))
      (let ((next-index (+ index+1 step -1)))
        (when (< next-index nw)
          (let ((value (aref tree next-index)))
            (when (<= value rank)
              (decf rank value)
              (incf index+1 step))))))
    (+ (* n-word-bits index+1)
       (the uint
            (%primitive unsigned-word-find-first-bit
                        (%primitive pdep
                                    (ash 1 (the (mod 64) rank))
                                    (sb-kernel:%vector-raw-bits bits index+1)))))))

(defun biset-find>= (biset x)
  (declare (optimize (speed 3))
           (uint x))
  (let ((rank (biset-count1 biset x)))
    (when (< rank (%biset-total biset))
      (biset-select biset rank))))

(defun biset-find> (biset x)
  (declare (optimize (speed 3))
           (uint x))
  (let ((rank (biset-count1 biset (+ x 1))))
    (when (< rank (%biset-total biset))
      (biset-select biset rank))))

(defun biset-find<= (biset x)
  (declare (optimize (speed 3))
           (uint x))
  (let ((rank (- (biset-count1 biset (+ x 1)) 1)))
    (when (>= rank 0)
      (biset-select biset rank))))

(defun biset-find< (biset x)
  (declare (optimize (speed 3))
           (uint x))
  (let ((rank (- (biset-count1 biset x) 1)))
    (when (>= rank 0)
      (biset-select biset rank))))
