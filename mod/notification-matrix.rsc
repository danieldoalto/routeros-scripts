#!rsc by RouterOS
# RouterOS script: mod/notification-matrix
# Copyright (c) 2013-2023 Michael Gisbers <michael@gisbers.de>
#                         Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# send notifications via Matrix
# https://git.eworm.de/cgit/routeros-scripts/about/doc/mod/notification-matrix.md

:global FlushMatrixQueue;
:global NotificationFunctions;
:global SendMatrix;
:global SendMatrix2;

# flush Matrix queue
:set FlushMatrixQueue do={
  :global MatrixQueue;

  :global IsFullyConnected;
  :global LogPrintExit2;

  :if ([ $IsFullyConnected ] = false) do={
    $LogPrintExit2 debug $0 ("System is not fully connected, not flushing.") false;
    :return false;
  }

  :local AllDone true;
  :local QueueLen [ :len $MatrixQueue ];

  :if ([ :len [ /system/scheduler/find where name=$0 ] ] > 0 && $QueueLen = 0) do={
    $LogPrintExit2 warning $0 ("Flushing Matrix messages from scheduler, but queue is empty.") false;
  }

  :foreach Id,Message in=$MatrixQueue do={
    :if ([ :typeof $Message ] = "array" ) do={
      :do {
        /tool/fetch check-certificate=yes-without-crl output=none http-method=post \
          ("https://" . $Message->"homeserver" . "/_matrix/client/r0/rooms/" . $Message->"room" . \
           "/send/m.room.message?access_token=" . $Message->"accesstoken") \
          http-data=("{ \"msgtype\": \"m.text\", \"body\": \"" . $Message->"plain" . "\"," . \
           "\"format\": \"org.matrix.custom.html\", \"formatted_body\": \"" . \
           $Message->"formatted" . "\" }") as-value;
        :set ($MatrixQueue->$Id);
      } on-error={
        $LogPrintExit2 debug $0 ("Sending queued Matrix message failed.") false;
        :set AllDone false;
      }
    }
  }

  :if ($AllDone = true && $QueueLen = [ :len $MatrixQueue ]) do={
    /system/scheduler/remove [ find where name=$0 ];
    :set MatrixQueue;
  }
}

# send notification via Matrix - expects one array argument
:set ($NotificationFunctions->"matrix") do={
  :local Notification $1;

  :global Identity;
  :global IdentityExtra;
  :global MatrixAccessToken;
  :global MatrixAccessTokenOverride;
  :global MatrixHomeServer;
  :global MatrixHomeServerOverride;
  :global MatrixQueue;
  :global MatrixRoom;
  :global MatrixRoomOverride;

  :global EitherOr;
  :global LogPrintExit2;
  :global SymbolForNotification;

  :local PrepareText do={
    :local Input [ :tostr $1 ];

    :if ([ :len $Input ] = 0) do={
      :return "";
    }

    :local Return "";
    :local Chars {
      "plain"={ "\\"; "\""; "\n" };
      "format"={ "\\"; "\""; "\n"; "&"; "<"; ">" };
    }
    :local Subs {
      "plain"={ "\\\\"; "\\\""; "\\n" };
      "format"={ "\\\\"; "&quot;"; "<br/>"; "&amp;"; "&lt;"; "&gt;" };
    }

    :for I from=0 to=([ :len $Input ] - 1) do={
      :local Char [ :pick $Input $I ];
      :local Replace [ :find ($Chars->$2) $Char ];

      :if ([ :typeof $Replace ] = "num") do={
        :set Char ($Subs->$2->$Replace);
      }
      :set Return ($Return . $Char);
    }

    :return $Return;
  }

  :local AccessToken [ $EitherOr ($MatrixAccessTokenOverride->($Notification->"origin")) $MatrixAccessToken ];
  :local HomeServer [ $EitherOr ($MatrixHomeServerOverride->($Notification->"origin")) $MatrixHomeServer ];
  :local Room [ $EitherOr ($MatrixRoomOverride->($Notification->"origin")) $MatrixRoom ];

  :if ([ :len $AccessToken ] = 0 || [ :len $HomeServer ] = 0 || [ :len $Room ] = 0) do={
    :return false;
  }

  :local Plain [ $PrepareText ("## [" . $IdentityExtra . $Identity . "] " . \
    ($Notification->"subject") . "\n```\n" . ($Notification->"message") . "\n```") "plain" ];
  :local Formatted ("<h2>" . [ $PrepareText ("[" . $IdentityExtra . $Identity . "] " . \
    ($Notification->"subject")) "format" ] . "</h2>" . "<pre><code>" . \
    [ $PrepareText ($Notification->"message") "format" ] . "</code></pre>");
  :if ([ :len ($Notification->"link") ] > 0) do={
    :set Plain ($Plain . "\\n" . [ $SymbolForNotification "link" ] . \
      [ $PrepareText ("[" . $Notification->"link" . "](" . $Notification->"link" . ")") "plain" ]);
    :set Formatted ($Formatted . "<br/>" . [ $SymbolForNotification "link" ] . \
      "<a href=\\\"" . [ $PrepareText ($Notification->"link") "format" ] . "\\\">" . \
      [ $PrepareText ($Notification->"link") "format" ] . "</a>");
  }

  :do {
    /tool/fetch check-certificate=yes-without-crl output=none http-method=post \
      ("https://" . $HomeServer . "/_matrix/client/r0/rooms/" . $Room . \
       "/send/m.room.message?access_token=" . $AccessToken) \
      http-data=("{ \"msgtype\": \"m.text\", \"body\": \"" . $Plain . "\"," . \
       "\"format\": \"org.matrix.custom.html\", \"formatted_body\": \"" . \
       $Formatted . "\" }") as-value;
  } on-error={
    $LogPrintExit2 info $0 ("Failed sending Matrix notification! Queuing...") false;

    :if ([ :typeof $MatrixQueue ] = "nothing") do={
      :set MatrixQueue ({});
    }
    :local Text ([ $SymbolForNotification "alarm-clock" ] . \
      "This message was queued since " . [ /system/clock/get date ] . \
      " " . [ /system/clock/get time ] . " and may be obsolete.");
    :set Plain ($Plain . "\\n" . $Text);
    :set Formatted ($Formatted . "<br/>" . $Text);
    :set ($MatrixQueue->[ :len $MatrixQueue ]) { room=$Room; \
      accesstoken=$AccessToken; homeserver=$HomeServer; \
      plain=$Plain; formatted=$Formatted };
    :if ([ :len [ /system/scheduler/find where name="\$FlushMatrixQueue" ] ] = 0) do={
      /system/scheduler/add name="\$FlushMatrixQueue" interval=1m start-time=startup \
        on-event=(":global FlushMatrixQueue; \$FlushMatrixQueue;");
    }
  }
}

# send notification via Matrix - expects at least two string arguments
:set SendMatrix do={
  :global SendMatrix2;

  $SendMatrix2 ({ subject=$1; message=$2; link=$3 });
}

# send notification via Matrix - expects one array argument
:set SendMatrix2 do={
  :local Notification $1;

  :global NotificationFunctions;

  ($NotificationFunctions->"matrix") ("\$NotificationFunctions->\"matrix\"") $Notification;
}
