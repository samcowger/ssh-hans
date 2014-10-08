{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import           Network.SSH.Packet ( SshIdent(..) )
import           Network.SSH.Server
import           Network.SSH.Messages
import           Network.SSH.UserAuth

import           Control.Monad ( forever )
import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import           Network
                     ( PortID(..), HostName, PortNumber, withSocketsDo, listenOn
                     , accept, Socket )
import           System.Directory ( doesFileExist )
import           System.IO ( Handle, hGetChar, hClose, hGetLine, hPutStrLn )


main :: IO ()
main  = withSocketsDo $
  do sock             <- listenOn (PortNumber 2200)
     (privKey,pubKey) <- loadKeys
     sshServer greeting privKey pubKey (mkServer sock)

greeting :: SshIdent
greeting  = SshIdent { sshProtoVersion    = "2.0"
                     , sshSoftwareVersion = "SSH_HaLVM_2.0"
                     , sshComments        = ""
                     }

mkServer :: Socket -> Server
mkServer sock = Server { sAccept = mkClient `fmap` accept sock }

emertensPubKey :: SshPubCert
emertensPubKey = SshPubRsa 35 25964490825869075456565315133613317015447736312131943669147612582029667946390134690084191987178033741047563824733221539952301173273051428643220871796453385502898146359379719478551566688165035231983895105682618937491831593971117244228476342572694601313183083372271655715242683226812033451044535273348848480673566791362842116607512585910646275323110393347168283422197812019692748590078493496117117347928046812539242074979883110348355966101089844487555867800780964100942711053618711644364210937596442391371529191584180796637895359042645640245619260247615859656368255762806020068608941320426880648559264824762770390985131

credentials :: [(S.ByteString, SshPubCert)]
credentials = [("emertens", emertensPubKey)]

mkClient :: (Handle,HostName,PortNumber) -> Client
mkClient (h,_,_) = Client { .. }
  where
  cGet   = S.hGetSome h
  cPut   = L.hPutStr  h
  cClose =   hClose   h

  cOpenShell h =
    do 
       forever $
         do xs <- hGetChar h
            print xs
            hPutStrLn h ("Echoing <" ++ xs : ">")

  cAuthHandler session_id username svc m@(SshAuthPublicKey alg key mbSig) =
    case lookup username credentials of
      Just pub | pub == key ->
       case mbSig of
         Nothing -> return (AuthPkOk alg key)
         Just sig
           | verifyPubKeyAuthentication session_id username svc alg key sig
                       -> return AuthAccepted
           | otherwise -> return (AuthFailed ["publickey"])
      _ -> return (AuthFailed ["publickey"])

  cAuthHandler session_id user svc m =
    do print (user,m)
       return (AuthFailed ["publickey"])

loadKeys :: IO (PrivateKey, PublicKey)
loadKeys  =
  do privExists <- doesFileExist "server.priv"
     pubExists  <- doesFileExist "server.pub"

     if privExists && pubExists
        then do priv <- readFile "server.priv"
                pub  <- readFile "server.pub"
                return (read priv, read pub) -- icky

        else do pair@(priv, pub) <- genKeyPair
                writeFile "server.priv" (show priv)
                writeFile "server.pub"  (show pub)
                return pair
