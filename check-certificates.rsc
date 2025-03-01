#!rsc by RouterOS
# RouterOS script: check-certificates
# Copyright (c) 2013-2023 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# check for certificate validity
# https://git.eworm.de/cgit/routeros-scripts/about/doc/check-certificates.md

:local 0 "check-certificates";
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:global CertRenewPass;
:global CertRenewTime;
:global CertRenewUrl;
:global CertWarnTime;
:global Identity;

:global CertificateAvailable
:global CertificateNameByCN;
:global IfThenElse;
:global LogPrintExit2;
:global ParseKeyValueStore;
:global SendNotification2;
:global SymbolForNotification;
:global UrlEncode;
:global WaitForFile;
:global WaitFullyConnected;

:local FormatExpire do={
  :global CharacterReplace;
  :return [ $CharacterReplace [ $CharacterReplace [ :tostr $1 ] "w" "w " ] "d" "d " ];
}

$WaitFullyConnected;

:foreach Cert in=[ /certificate/find where !revoked !ca !scep-url expires-after<$CertRenewTime ] do={
  :local CertVal [ /certificate/get $Cert ];

  :do {
    :if ([ :len $CertRenewUrl ] = 0) do={
      $LogPrintExit2 info $0 ("No CertRenewUrl given.") true;
    }
    $LogPrintExit2 info $0 ("Attempting to renew certificate " . ($CertVal->"name") . ".") false;

    :foreach Type in={ ".pem"; ".p12" } do={
      :local CertFileName ([ $UrlEncode ($CertVal->"common-name") ] . $Type);
      :do {
        /tool/fetch check-certificate=yes-without-crl \
            ($CertRenewUrl . $CertFileName) dst-path=$CertFileName as-value;
        $WaitForFile $CertFileName;

        :local DecryptionFailed true;
        :foreach PassPhrase in=$CertRenewPass do={
          :local Result [ /certificate/import file-name=$CertFileName passphrase=$PassPhrase as-value ];
          :if ($Result->"decryption-failures" = 0) do={
            :set DecryptionFailed false;
          }
        }
        /file/remove [ find where name=$CertFileName ];

        :if ($DecryptionFailed = true) do={
          $LogPrintExit2 warning $0 ("Decryption failed for certificate file " . $CertFileName) false;
        }

        :foreach CertInChain in=[ /certificate/find where name~("^" . $CertFileName . "_[0-9]+\$") common-name!=($CertVal->"common-name") ] do={
          $CertificateNameByCN [ /certificate/get $CertInChain common-name ];
        }
      } on-error={
        $LogPrintExit2 debug $0 ("Could not download certificate file " . $CertFileName) false;
      }
    }

    :local CertNew [ /certificate/find where common-name=($CertVal->"common-name") fingerprint!=[ :tostr ($CertVal->"fingerprint") ] expires-after>$CertRenewTime ];
    :local CertNewVal [ /certificate/get $CertNew ];

    :if ([ $CertificateAvailable ([ $ParseKeyValueStore ($CertNewVal->"issuer") ]->"CN") ] = false) do={
      $LogPrintExit2 warning $0 ("The certificate chain is not available!") false;
    }

    :if ($Cert != $CertNew) do={
      $LogPrintExit2 debug $0 ("Certificate '" . $CertVal->"name" . "' was not updated, but replaced.") false;

      :if (($CertVal->"private-key") = true && ($CertVal->"private-key") != ($CertNewVal->"private-key")) do={
        /certificate/remove $CertNew;
        $LogPrintExit2 warning $0 ("Old certificate '" . ($CertVal->"name") . "' has a private key, new certificate does not. Aborting renew.") true;
      }

      /ip/service/set certificate=($CertNewVal->"name") [ find where certificate=($CertVal->"name") ];

      /ip/ipsec/identity/set certificate=($CertNewVal->"name") [ find where certificate=($CertVal->"name") ];
      /ip/ipsec/identity/set remote-certificate=($CertNewVal->"name") [ find where remote-certificate=($CertVal->"name") ];

      /ip/hotspot/profile/set ssl-certificate=($CertNewVal->"name") [ find where ssl-certificate=($CertVal->"name") ];

      /certificate/remove $Cert;
      /certificate/set $CertNew name=($CertVal->"name");
    }

    $SendNotification2 ({ origin=$0; \
      subject=([ $SymbolForNotification "lock-with-ink-pen" ] . "Certificate renewed"); \
      message=("A certificate on " . $Identity . " has been renewed.\n\n" . \
        "Name:        " . ($CertVal->"name") . "\n" . \
        "CommonName:  " . ($CertNewVal->"common-name") . "\n" . \
        "Private key: " . [ $IfThenElse (($CertNewVal->"private-key") = true) "available" "missing" ] . "\n" . \
        "Fingerprint: " . ($CertNewVal->"fingerprint") . "\n" . \
        "Issuer:      " . ([ $ParseKeyValueStore ($CertNewVal->"issuer") ]->"CN") . "\n" . \
        "Validity:    " . ($CertNewVal->"invalid-before") . " to " . ($CertNewVal->"invalid-after") . "\n" . \
        "Expires in:  " . [ $FormatExpire ($CertNewVal->"expires-after") ]); silent=true });
    $LogPrintExit2 info $0 ("The certificate " . ($CertVal->"name") . " has been renewed.") false;
  } on-error={
    $LogPrintExit2 debug $0 ("Could not renew certificate " . ($CertVal->"name") . ".") false;
  }
}

:foreach Cert in=[ /certificate/find where !revoked !scep-url !(expires-after=[]) \
                   expires-after<$CertWarnTime !(fingerprint=[]) ] do={
  :local CertVal [ /certificate/get $Cert ];

  :if ([ :len [ /certificate/scep-server/find where ca-cert=($CertVal->"ca") ] ] > 0) do={
    $LogPrintExit2 debug $0 ("Certificate \"" . ($CertVal->"name") . "\" is handled by SCEP, skipping.") false;
  } else={
    :local State [ $IfThenElse (($CertVal->"expired") = true) "expired" "is about to expire" ];

    $SendNotification2 ({ origin=$0; \
      subject=([ $SymbolForNotification "warning-sign" ] . "Certificate warning!"); \
      message=("A certificate on " . $Identity . " " . $State . ".\n\n" . \
        "Name:        " . ($CertVal->"name") . "\n" . \
        "CommonName:  " . ($CertVal->"common-name") . "\n" . \
        "Private key: " . [ $IfThenElse (($CertVal->"private-key") = true) "available" "missing" ] . "\n" . \
        "Fingerprint: " . ($CertVal->"fingerprint") . "\n" . \
        "Issuer:      " . ($CertVal->"ca") . ([ $ParseKeyValueStore ($CertVal->"issuer") ]->"CN") . "\n" . \
        "Validity:    " . ($CertVal->"invalid-before") . " to " . ($CertVal->"invalid-after") . "\n" . \
        "Expires in:  " . [ $IfThenElse (($CertVal->"expired") = true) "expired" [ $FormatExpire ($CertVal->"expires-after") ] ]) });
    $LogPrintExit2 info $0 ("The certificate " . ($CertVal->"name") . " " . $State . \
        ", it is invalid after " . ($CertVal->"invalid-after") . ".") false;
  }
}
