{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Emanote.Model.Meta where

import Control.Lens.Operators as Lens ((^.))
import Data.Aeson (FromJSON)
import qualified Data.Aeson as Aeson
import qualified Data.IxSet.Typed as Ix
import Emanote.Model (Model, modelLookupNote, modelSData)
import Emanote.Model.Note (noteMeta)
import Emanote.Model.SData (sdataValue)
import qualified Emanote.Model.SData as SData
import qualified Emanote.Route as R
import qualified Emanote.Route.Ext as Ext
import Emanote.Route.Linkable
import Relude.Extra.Map (StaticMap (lookup))

-- | Look up a specific key in the meta for a given route.
lookupMeta :: FromJSON a => a -> NonEmpty Text -> LinkableLMLRoute -> Model -> a
lookupMeta x k r =
  lookupMetaFrom x k . getEffectiveRouteMeta r

-- TODO: Use https://hackage.haskell.org/package/lens-aeson
lookupMetaFrom :: forall a. FromJSON a => a -> NonEmpty Text -> Aeson.Value -> a
lookupMetaFrom x (k :| ks) meta =
  fromMaybe x $ do
    Aeson.Object obj <- pure meta
    val <- lookup k obj
    case nonEmpty ks of
      Nothing -> resultToMaybe $ Aeson.fromJSON val
      Just ks' -> pure $ lookupMetaFrom x ks' val
  where
    resultToMaybe :: Aeson.Result b -> Maybe b
    resultToMaybe = \case
      Aeson.Error _ -> Nothing
      Aeson.Success b -> pure b

-- | Get the (final) metadata of a note at the given route, by merging it with
-- the defaults specified in parent routes all the way upto index.yaml.
getEffectiveRouteMeta :: LinkableLMLRoute -> Model -> Aeson.Value
getEffectiveRouteMeta mr model =
  let defaultFiles = R.routeInits @'Ext.Yaml (coerce $ someLinkableLMLRouteCase mr)
      defaults = flip mapMaybe (toList defaultFiles) $ \r -> do
        v <- fmap (^. sdataValue) . Ix.getOne . Ix.getEQ r $ model ^. modelSData
        guard $ v /= Aeson.Null
        pure v
      frontmatter = do
        x <- (^. noteMeta) <$> modelLookupNote mr model
        guard $ x /= Aeson.Null
        pure x
      metas = defaults <> maybe mempty one frontmatter
   in maybe Aeson.Null SData.mergeAesons $ nonEmpty metas