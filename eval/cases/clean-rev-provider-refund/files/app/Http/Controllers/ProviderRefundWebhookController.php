<?php

namespace App\Http\Controllers;

use App\Models\Payment;
use App\Models\Refund;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * refund.succeeded events for refunds made outside our app (the provider dashboard,
 * the provider's support). Refunds we start ourselves carry our idempotency key
 * (refund-{id}) and are booked by RefundService and ResolvePendingRefunds, so they
 * are skipped here. The signature is checked by the VerifyPspSignature middleware.
 *
 * Payload: {"id": "evt_...", "type": "refund.succeeded", "data": {"refund_id": "...",
 * "charge_reference": "...", "amount_cents": 500, "currency": "EUR",
 * "idempotency_key": null}}
 */
final class ProviderRefundWebhookController
{
    public function __invoke(Request $request): Response
    {
        if ($request->input('type') !== 'refund.succeeded') {
            return response()->noContent(); // other types are handled by PspWebhookController
        }

        if ($request->input('data.idempotency_key') !== null) {
            return response()->noContent(); // started by us
        }

        $eventId = (string) $request->input('id');
        $refundId = (string) $request->input('data.refund_id');
        // The provider's id of the charge this refund belongs to: payments.psp_reference,
        // unique per charge, so a rebill refund lands on that rebill.
        $chargeReference = (string) $request->input('data.charge_reference');
        $amountCents = (int) $request->input('data.amount_cents');
        $currency = (string) $request->input('data.currency');

        if ($refundId === '' || $chargeReference === '') {
            return response('missing refund or charge reference', 422);
        }

        DB::transaction(function () use ($eventId, $refundId, $chargeReference, $amountCents, $currency) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'psp', 'event_id' => $eventId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return;
            }

            $payment = Payment::where('psp_reference', $chargeReference)->lockForUpdate()->first();
            if ($payment === null || $payment->status !== 'succeeded') {
                // Rolled back with the processed_events row: the provider retries, and the
                // error shows up in the alerts until someone looks.
                throw new \UnexpectedValueException("refund {$refundId}: no settled payment for charge {$chargeReference}");
            }
            // Under the payment lock: one row per provider refund.
            if (Refund::where('payment_id', $payment->id)->where('psp_reference', $refundId)->exists()) {
                return;
            }
            // refunded_cents includes our own pending refunds, so the cap covers every refund
            // of this payment, not only this one.
            if ($currency !== $payment->currency || $amountCents <= 0
                || $payment->refunded_cents + $amountCents > $payment->amount_cents) {
                Log::warning('provider refund does not fit the payment', [
                    'refund_id' => $refundId, 'payment_id' => $payment->id,
                    'amount_cents' => $amountCents, 'refunded_cents' => $payment->refunded_cents,
                ]);
                throw new \UnexpectedValueException("refund {$refundId} does not fit payment {$payment->id}");
            }

            Refund::create([
                'payment_id' => $payment->id,
                'amount_cents' => $amountCents,
                'reason' => "provider:{$refundId}",
                'status' => 'succeeded',
                'psp_reference' => $refundId,
            ]);
            $payment->refunded_cents += $amountCents;
            $payment->save();
        });

        return response()->noContent();
    }
}
