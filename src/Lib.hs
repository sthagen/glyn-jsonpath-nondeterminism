{-# LANGUAGE ScopedTypeVariables #-}

module Lib
    ( Nodelist
    , Query
    , root
    , childWildcard
    , descendantWildcard
    ) where

import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import Data.List (permutations)
import Data.Vector (toList, (!), Vector)

type Nodelist = [Value] -- omit locations

 -- Generalise a RFC 9535 query to return a list of possible results (nodelists).
 -- If there is one item in the list, the query is deterministic.
 -- If there is more than one item in the list, the query is non-deterministic.
type Query = Nodelist -> [Nodelist]

-- root is a query corresponding to $
-- It is deterministic, so it returns one nodelist.
root :: Value -> [Nodelist]
root v = [[v]]

-- childWildcard is a query corresponding to [*]
-- It is non-deterministic when applied to an object with more than one member.
childWildcard :: Query
childWildcard [] = [[]]
childWildcard (n:ns) = do
    l :: Nodelist <- children n
    r :: Nodelist <- childWildcard ns
    return (l ++ r)
    where children :: Value -> [Nodelist] -- input value must be a child of the argument
          children (Object o) = permutations $ KM.elems o
          children (Array a) = [toList a]
          children _ = [[]]

-- descendantWildcard is a query corresponding to ..[*]
-- It is non-deterministic when it traverses over an object with more than one member
descendantWildcard :: Query
descendantWildcard [] = [[]]
descendantWildcard (n:ns) = do
    l :: Nodelist <- map (map snd) $ filter validDescendantOrdering $ permutations $ descendants [] n
    r :: Nodelist <- descendantWildcard ns
    return (l ++ r)
    where descendants :: Path -> Value -> [(Path,Value)] -- input value must be a child of the argument at location denoted by the input path
          descendants p (Object o) = objectChildren p o ++ [ x | (k,v) <- KM.toList o, x <- descendants (p++[Member $ K.toString k]) v]
          descendants p (Array a) = arrayChildren p a ++ [x | n <- [0..(length a - 1)], x <- descendants (p++[Element n]) $ a ! n]
          descendants _ _ = []

type Path = [PathItem]
data PathItem = Member String | Element Int
                deriving Eq

objectChildren :: Path -> KM.KeyMap Value -> [(Path, Value)]
objectChildren p km = [(p++[Member $ K.toString k],v) | (k,v) <- KM.toList km]

arrayChildren :: Path -> Vector Value -> [(Path, Value)]
arrayChildren p v = [(p++[Element i], v ! i) | i <- [0.. length (toList v) - 1]]


validDescendantOrdering :: [(Path,Value)] -> Bool
validDescendantOrdering [] = True
validDescendantOrdering [_] = True
validDescendantOrdering (x:y:xs) = not (invalidBefore x y) && validDescendantOrdering (x:xs) && validDescendantOrdering (y:xs)

invalidBefore :: (Path,Value) -> (Path,Value) -> Bool
invalidBefore x y = childBeforeParent x y || arrayElementsOutOfOrder x y

childBeforeParent :: (Path,Value) -> (Path,Value) -> Bool
childBeforeParent ([],_) (_,_) = False
childBeforeParent (p,_) (q,_) = init p == q
    
arrayElementsOutOfOrder :: (Path,Value) -> (Path,Value) -> Bool
arrayElementsOutOfOrder ([],_) (_,_) = False  
arrayElementsOutOfOrder (_,_) ([],_) = False  
arrayElementsOutOfOrder ([Element m],_) ([Element n],_) = m >= n  
arrayElementsOutOfOrder (p:ps,v) (q:qs,w) = p == q && arrayElementsOutOfOrder (ps,v) (qs,w) 