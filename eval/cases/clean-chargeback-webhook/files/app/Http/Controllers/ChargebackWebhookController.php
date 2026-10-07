<?php

namespace App\Http\Controllers;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

/** chargeback.created events. The signature is checked by the VerifyPspSignature middleware. */
final class ChargebackWebhookController
{
    public function __construct(private Ledger $ledger)
    {
    }

    public function __invoke(Request $request): Response
    {
        $eventId = (string) $request->input('id');
        $reference = (string) $request->input('data.reference');
        // What the provider took back. After a partial refund it is less than the payment.
        $amountCents = (int) $request->input('data.amount_cents');
        $currency = (string) $request->input('data.currency');

        DB::transaction(function () use ($eventId, $reference, $amountCents, $currency) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'psp', 'event_id' => $eventId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return; // a retry of an event we already handled
            }

            $payment = Payment::where('psp_reference', $reference)->lockForUpdate()->first();
            if ($payment === null || ! in_array($payment->status, ['succeeded', 'charged_back'], true)) {
                // Not ours yet, or not settled: fail, so the provider sends it again and the
                // event is not marked as processed.
                throw new \UnexpectedValueException("chargeback {$eventId} for an unknown or unsettled payment");
            }
            if ($payment->status === 'charged_back') {
                return; // one chargeback per payment, already booked
            }
            // Refunds (also pending ones) are already counted in refunded_cents; the provider
            // cannot take back more than is left of the payment.
            $left = $payment->amount_cents - $payment->refunded_cents;
            if ($currency !== $payment->currency || $amountCents <= 0 || $amountCents > $left) {
                throw new \UnexpectedValueException("chargeback {$eventId} does not match payment {$payment->id}");
            }

            // The top-up moved the money out of psp_clearing; the provider has now kept it, so
            // psp_clearing gets it back and the loss stays on the chargebacks account (a system
            // account that may go negative, like psp_clearing). Taking it back from the user
            // is a separate decision, made by support.
            $this->ledger->transfer(
                "chargeback:{$payment->id}",
                Account::system('chargebacks', $payment->currency),
                Account::system('psp_clearing', $payment->currency),
                $amountCents,
                'chargeback',
            );
            $payment->status = 'charged_back';
            $payment->save();
        });

        return response()->noContent();
    }
}
