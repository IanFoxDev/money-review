<?php

namespace App\Http\Controllers;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Instant payment notifications from CardHub hosted checkout, used for top-ups. We
 * create a pending payment, send the customer to the hosted page with
 * merchant_order_id = payments.id, and CardHub posts the result here.
 * The signature is checked by the VerifyCardHubSignature middleware.
 */
final class CardHubIpnController
{
    public function __construct(private Ledger $ledger)
    {
    }

    public function __invoke(Request $request): Response
    {
        $notificationId = (string) $request->input('notification_id');
        $paymentId = (int) $request->input('merchant_order_id');
        $transactionId = (string) $request->input('transaction_id');
        $status = strtolower(trim((string) $request->input('status')));
        $amountCents = (int) $request->input('amount');   // minor units
        $currency = strtoupper((string) $request->input('currency'));

        DB::transaction(function () use ($notificationId, $paymentId, $transactionId, $status, $amountCents, $currency) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'cardhub', 'event_id' => $notificationId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return; // CardHub resends until it gets a 2xx
            }

            $payment = Payment::whereKey($paymentId)->lockForUpdate()->first();
            if ($payment === null) {
                Log::warning('cardhub ipn for an unknown order', ['notification_id' => $notificationId, 'order' => $paymentId]);

                return;
            }
            if ($payment->status !== 'pending') {
                return; // already final, a late or repeated result
            }

            Log::info('cardhub ipn', [
                'payment_id' => $payment->id, 'status' => $status,
                'amount' => $amountCents, 'currency' => $currency,
            ]);

            if ($status === 'completed') {
                $payment->status = 'succeeded';
                $payment->psp_reference = $transactionId;
                $payment->save();

                $this->ledger->transfer(
                    "payment:{$payment->id}",
                    Account::system('psp_clearing', $payment->currency),
                    Account::forUser($payment->user_id, $payment->currency),
                    $payment->amount_cents,
                    'top_up',
                );
            } elseif (in_array($status, ['declined', 'canceled', 'expired'], true)) {
                $payment->status = 'failed';
                $payment->psp_reference = $transactionId;
                $payment->save();
            }
            // Other statuses (pending, 3ds) are intermediate: a final IPN follows.
        });

        return response()->noContent();
    }
}
