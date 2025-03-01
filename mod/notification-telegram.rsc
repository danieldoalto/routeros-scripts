#!rsc by RouterOS
# RouterOS script: mod/notification-telegram
# Copyright (c) 2013-2023 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# send notifications via Telegram
# https://git.eworm.de/cgit/routeros-scripts/about/doc/mod/notification-telegram.md

:global FlushTelegramQueue;
:global NotificationFunctions;
:global SendTelegram;
:global SendTelegram2;

# flush telegram queue
:set FlushTelegramQueue do={
  :global TelegramQueue;

  :global IsFullyConnected;
  :global LogPrintExit2;

  :if ([ $IsFullyConnected ] = false) do={
    $LogPrintExit2 debug $0 ("System is not fully connected, not flushing.") false;
    :return false;
  }

  :local AllDone true;
  :local QueueLen [ :len $TelegramQueue ];

  :if ([ :len [ /system/scheduler/find where name=$0 ] ] > 0 && $QueueLen = 0) do={
    $LogPrintExit2 warning $0 ("Flushing Telegram messages from scheduler, but queue is empty.") false;
  }

  :foreach Id,Message in=$TelegramQueue do={
    :if ([ :typeof $Message ] = "array" ) do={
      :do {
        /tool/fetch check-certificate=yes-without-crl output=none http-method=post \
          ("https://api.telegram.org/bot" . ($Message->"tokenid") . "/sendMessage") \
          http-data=("chat_id=" . ($Message->"chatid") . \
          "&disable_notification=" . ($Message->"silent") . \
          "&reply_to_message_id=" . ($Notification->"replyto") . \
          "&disable_web_page_preview=true&parse_mode=" . ($Message->"parsemode") . \
          "&text=" . ($Message->"text")) as-value;
        :set ($TelegramQueue->$Id);
      } on-error={
        $LogPrintExit2 debug $0 ("Sending queued Telegram message failed.") false;
        :set AllDone false;
      }
    }
  }

  :if ($AllDone = true && $QueueLen = [ :len $TelegramQueue ]) do={
    /system/scheduler/remove [ find where name=$0 ];
    :set TelegramQueue;
  }
}

# send notification via telegram - expects one array argument
:set ($NotificationFunctions->"telegram") do={
  :local Notification $1;

  :global Identity;
  :global IdentityExtra;
  :global TelegramChatId;
  :global TelegramChatIdOverride;
  :global TelegramFixedWidthFont;
  :global TelegramQueue;
  :global TelegramTokenId;
  :global TelegramTokenIdOverride;

  :global CertificateAvailable;
  :global CharacterReplace;
  :global EitherOr;
  :global IfThenElse;
  :global LogPrintExit2;
  :global SymbolForNotification;
  :global UrlEncode;

  :local EscapeMD do={
    :global TelegramFixedWidthFont;

    :global CharacterReplace;
    :global IfThenElse;

    :if ($TelegramFixedWidthFont != true) do={
      :return ($1 . [ $IfThenElse ($2 = "body") ("\n") "" ]);
    }

    :local Return $1;
    :local Chars {
      "body"={ "\\"; "`" };
      "plain"={ "_"; "*"; "["; "]"; "("; ")"; "~"; "`"; ">";
                "#"; "+"; "-"; "="; "|"; "{"; "}"; "."; "!" };
    }
    :foreach Char in=($Chars->$2) do={
      :set Return [ $CharacterReplace $Return $Char ("\\" . $Char) ];
    }

    :if ($2 = "body") do={
      :return ("```\n" . $Return . "\n```");
    }

    :return $Return;
  }

  :local ChatId [ $EitherOr ($Notification->"chatid") \
    [ $EitherOr ($TelegramChatIdOverride->($Notification->"origin")) $TelegramChatId ] ];
  :local TokenId [ $EitherOr ($TelegramTokenIdOverride->($Notification->"origin")) $TelegramTokenId ];

  :if ([ :len $TokenId ] = 0 || [ :len $ChatId ] = 0) do={
    :return false;
  }

  :local Truncated false;
  :local Text ("*__" . [ $EscapeMD ("[" . $IdentityExtra . $Identity . "] " . \
    ($Notification->"subject")) "plain" ] . "__*\n\n");
  :local LenSubject [ :len $Text ];
  :local LenMessage [ :len ($Notification->"message") ];
  :local LenLink [ :len ($Notification->"link") ];
  :local LenSum ($LenSubject + $LenMessage + $LenLink);
  :if ($LenSum > 3968) do={
    :set Text ($Text . [ $EscapeMD ([ :pick ($Notification->"message") 0 (3840 - $LenSubject - $LenLink) ] . "...") "body" ]);
    :set Truncated true;
  } else={
    :set Text ($Text . [ $EscapeMD ($Notification->"message") "body" ]);
  }
  :if ($LenLink > 0) do={
    :set Text ($Text . "\n" . [ $SymbolForNotification "link" ] . [ $EscapeMD ($Notification->"link") "plain" ]);
  }
  :if ($Truncated = true) do={
    :set Text ($Text . "\n" . [ $SymbolForNotification "scissors" ] . \
      [ $EscapeMD ("The message was too long and has been truncated, cut off " . \
      (($LenSum - [ :len $Text ]) * 100 / $LenSum) . "%!") "plain" ]);
  }
  :set Text [ $UrlEncode $Text ];
  :local ParseMode [ $IfThenElse ($TelegramFixedWidthFont = true) "MarkdownV2" "" ];

  :do {
    :if ([ $CertificateAvailable "Go Daddy Secure Certificate Authority - G2" ] = false) do={
      $LogPrintExit2 warning $0 ("Downloading required certificate failed.") true;
    }
    /tool/fetch check-certificate=yes-without-crl output=none http-method=post \
      ("https://api.telegram.org/bot" . $TokenId . "/sendMessage") \
      http-data=("chat_id=" . $ChatId . "&disable_notification=" . ($Notification->"silent") . \
      "&reply_to_message_id=" . ($Notification->"replyto") . \
      "&disable_web_page_preview=true&parse_mode=" . $ParseMode . "&text=" . $Text) as-value;
  } on-error={
    $LogPrintExit2 info $0 ("Failed sending telegram notification! Queuing...") false;

    :if ([ :typeof $TelegramQueue ] = "nothing") do={
      :set TelegramQueue ({});
    }
    :set Text ($Text . [ $UrlEncode ("\n" . [ $SymbolForNotification "alarm-clock" ] . \
      [ $EscapeMD ("This message was queued since " . [ /system/clock/get date ] . \
      " " . [ /system/clock/get time ] . " and may be obsolete.") "plain" ]) ]);
    :set ($TelegramQueue->[ :len $TelegramQueue ]) { chatid=$ChatId; tokenid=$TokenId;
      parsemode=$ParseMode; text=$Text; silent=($Notification->"silent");
      replyto=($Notification->"replyto") };
    :if ([ :len [ /system/scheduler/find where name="\$FlushTelegramQueue" ] ] = 0) do={
      /system/scheduler/add name="\$FlushTelegramQueue" interval=1m start-time=startup \
        on-event=(":global FlushTelegramQueue; \$FlushTelegramQueue;");
    }
  }
}

# send notification via telegram - expects at least two string arguments
:set SendTelegram do={
  :global SendTelegram2;

  $SendTelegram2 ({ subject=$1; message=$2; link=$3; silent=$4 });
}

# send notification via telegram - expects one array argument
:set SendTelegram2 do={
  :local Notification $1;

  :global NotificationFunctions;

  ($NotificationFunctions->"telegram") ("\$NotificationFunctions->\"telegram\"") $Notification;
}
