{-# LANGUAGE UnicodeSyntax #-}
module MasterPlan.Backend.Identity (render) where

import           Control.Monad.RWS
import           Data.Char          (toLower)
import           Data.List          (intercalate)
import qualified Data.List.NonEmpty as NE
import qualified Data.Map           as M
import           Data.Maybe         (fromMaybe)
import           MasterPlan.Data

-- |Plain text renderer
render ∷ ProjectSystem → String
render (ProjectSystem bs) = snd $ evalRWS (renderName "root") () bs

type RenderMonad = RWS () String (M.Map String ProjectBinding)

renderLine ∷ String → RenderMonad ()
renderLine s = tell s >> tell ";\n"

renderName ∷ String → RenderMonad ()
renderName projName =
  do mb <- gets $ M.lookup projName
     case mb of
       Nothing -> pure ()
       Just b  -> do renderBinding projName b
                     tell "\n" -- empty line to separate bindings
                     modify $ M.delete projName
                     let names = case b of
                                  ExpressionProj _ e -> dependencies e
                                  _                  -> []
                     mapM_ renderName names

dependencies ∷ Project → [String]
dependencies (RefProj n)       = [n]
dependencies (SumProj ps)      = concatMap dependencies ps
dependencies (SequenceProj ps) = concatMap dependencies ps
dependencies (ProductProj ps)  = concatMap dependencies ps

renderProps ∷ String → ProjectProperties → RenderMonad ()
renderProps projName p = do renderProperty projName "name" (title p) "root" id
                            renderProperty projName "description" (description p) Nothing $ fromMaybe ""
                            renderProperty projName "url" (url p) Nothing $ fromMaybe ""
                            renderProperty projName "owner" (owner p) Nothing $ fromMaybe ""

renderProperty ∷ Eq a ⇒ String → String → a → a → (a → String) → RenderMonad ()
renderProperty projName propName val def toStr
  | val == def = pure ()
  | otherwise = renderLine $ propName ++ "(" ++ projName ++ ") = " ++ toStr val

renderBinding ∷ String → ProjectBinding → RenderMonad ()
renderBinding projName (UnconsolidatedProj p) = renderProps projName p
renderBinding projName (p@TaskProj {}) =
    do renderProps projName $ props p
       renderProperty projName "cost" (reportedCost p) 0 show
       renderProperty projName "status" (reportedStatus p) Ready (map toLower . show)
       renderProperty projName "trust" (reportedTrust p) 1 percentage
       renderProperty projName "progress" (reportedProgress p) 0 percentage
  where
    percentage n = show (n * 100) ++ "%"


renderBinding projName (ExpressionProj pr e) =
    do renderProps projName pr
       renderLine $ projName ++ " = " ++ expressionToStr e
  where
    combinedEToStr op ps = let sube = map expressionToStr $ NE.toList ps
                            in intercalate (" " ++ op ++ " ") sube

    expressionToStr (RefProj n)       = n
    expressionToStr (ProductProj ps)  = combinedEToStr "*" ps
    expressionToStr (SequenceProj ps) = combinedEToStr "->" ps
    expressionToStr (SumProj ps)      = combinedEToStr "*" ps
