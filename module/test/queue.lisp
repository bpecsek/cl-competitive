(defpackage :cp/test/queue
  (:use :cl :fiveam :cp/queue)
  (:import-from :cp/test/base #:base-suite)
  (:import-from :cp/queue #:queue-list))
(in-package :cp/test/queue)
(in-suite base-suite)

(test queue
  (let ((que (make-queue '(2 3))))
    (is (null (queue-empty-p que)))
    (enqueue-front 1 que)
    (is (= 1 (dequeue que)))
    (enqueue 4 que)
    (is (= 2 (dequeue que)))
    (is (= 3 (dequeue que)))
    (is (= 4 (queue-peek que)))
    (is (= 4 (dequeue que)))
    (is (null (queue-peek que)))
    (is (null (dequeue que)))
    (is (queue-empty-p que))
    (enqueue-front 1 que)
    (is (null (queue-empty-p que)))
    (is (= 1 (queue-peek que)))))