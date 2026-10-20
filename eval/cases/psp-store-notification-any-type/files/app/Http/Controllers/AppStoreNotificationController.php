<?php

namespace App\Http\Controllers;

use App\Models\Payment;
use App\Models\Subscription;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

/**
 * App Store server notifications. The VerifyAppStoreSignature middleware checks the
 * signed payload and puts the decoded notification into the request as "decoded".
 */
final class AppStoreNotificationController
{
    public function __invoke(Request $request): Response
    {
        $notification = (array) $request->input('decoded');
        $type = (string) $notification['notificationType'];
        $tx = (array) $notification['data']['transaction'];

        DB::transaction(function () use ($notification, $tx) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'appstore', 'event_id' => $notification['notificationUUID'], 'created_at' => now(),
            ]);
            if ($first === 0) {
                return; // Apple retried this notification
            }

            $userId = (int) $tx['appAccountToken'];
            Payment::create([
                'user_id' => $userId,
                'amount_cents' => intdiv((int) $tx['price'], 10), // Apple sends milliunits
                'currency' => (string) $tx['currency'],
                'status' => 'succeeded',
                'psp_reference' => 'appstore:' . $notification['notificationUUID'],
            ]);

            Subscription::where('user_id', $userId)->where('status', 'active')
                ->update(['updated_at' => now()]);
        });

        return response()->noContent();
    }
}
