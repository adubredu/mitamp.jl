(define (problem pb2)
   (:domain blocksworld)
   (:objects a b)
   (:init (on a b)  (clear a) (arm-empty))
   (:goal (and (holding b))))