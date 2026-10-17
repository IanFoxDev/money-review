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
    private const FAILED = ['declined', 'canceled', 'expired'];
    private const INTERMEDIATE = ['pending', '3ds_required'];

    public function __construct(private Ledger $ledger)
    {
    }

    public function __invoke(Request $request): Response
    {
        $notificationId = (string) $request->input('notification_id');
        $paymentId = (int) $request->input('merchant_order_id');
        $transactionId = (string) $request->input('transaction_id');
        $status = strtolower(trim((string) $request->input('status')));
        $amount = $request->input('amount');
        $currency = strtoupper(trim((string) $request->input('currency')));

        if ($notificationId === '' || $transactionId === '' || ! is_numeric($amount) || (string) (int) $amount !== (string) $amount) {
            return response('malformed', 422);
        }
        $amountCents = (int) $amount; // CardHub sends minor units as an integer

        DB::transaction(function () use ($notificationId, $paymentId, $transactionId, $status, $amountCents, $currency) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'cardhub', 'event_id' => $notificationId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return; // CardHub resends until it gets a 2xx
            }

            $payment = Payment::whereKey($paymentId)->lockForUpdate()->first();
            if ($payment === null) {
                // Rolls back the processed_events row, so the retry is handled once the order exists.
                throw new \UnexpectedValueException("cardhub ipn {$notificationId} for unknown order {$paymentId}");
            }
            if ($payment->status !== 'pending') {
                return; // already final, a late or repeated result
            }

            if ($status === 'completed') {
                if ($amountCents !== (int) $payment->amount_cents || $currency !== $payment->currency) {
                    // Paid something other than the order: no credit, support settles it with the customer.
                    $payment->status = 'amount_mismatch';
                    $payment->psp_reference = $transactionId;
                    $payment->save();
                    Log::warning('cardhub ipn amount mismatch', [
                        'payment_id' => $payment->id,
                        'expected' => [$payment->amount_cents, $payment->currency],
                        'reported' => [$amountCents, $currency],
                    ]);

                    return;
                }

                $payment->status = 'succeeded';
                $payment->psp_reference = $transactionId;
                $payment->save();

                // Same key as the PSP webhook path, so the payment is credited once whichever arrives first.
                $this->ledger->transfer(
                    "payment:{$payment->id}",
                    Account::system('psp_clearing', $payment->currency),
                    Account::forUser($payment->user_id, $payment->currency),
                    $payment->amount_cents,
                    'top_up',
                );

                return;
            }

            if (in_array($status, self::FAILED, true)) {
                $payment->status = 'failed';
                $payment->psp_reference = $transactionId;
                $payment->save();

                return;
            }

            if (! in_array($status, self::INTERMEDIATE, true)) {
                // A status we do not know: refuse it, CardHub retries and the error alerts us.
                throw new \UnexpectedValueException("cardhub ipn {$notificationId}: unknown status {$status}");
            }
            // Intermediate: a final IPN follows.
        });

        return response()->noContent();
    }
}
