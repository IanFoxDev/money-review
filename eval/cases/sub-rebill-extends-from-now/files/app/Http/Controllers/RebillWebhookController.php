<?php

namespace App\Http\Controllers;

use App\Models\Payment;
use App\Models\Subscription;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * agreement.charged events: the provider charged a recurring agreement on its
 * monthly schedule (it retries a failed card for up to three days, so the event can
 * come a few days after the period ended). We record the payment and give the user
 * another month. The signature is checked by the VerifyPspSignature middleware.
 *
 * Payload: {"id": "evt_...", "type": "agreement.charged", "data": {"agreement_id": "...",
 * "charge_reference": "...", "amount_cents": 999, "currency": "EUR"}}
 */
final class RebillWebhookController
{
    public function __invoke(Request $request): Response
    {
        if ($request->input('type') !== 'agreement.charged') {
            return response()->noContent();
        }

        $eventId = (string) $request->input('id');
        $agreementId = (string) $request->input('data.agreement_id');
        $chargeReference = (string) $request->input('data.charge_reference');
        $amountCents = (int) $request->input('data.amount_cents');
        $currency = (string) $request->input('data.currency');

        DB::transaction(function () use ($eventId, $agreementId, $chargeReference, $amountCents, $currency) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'psp', 'event_id' => $eventId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return;
            }

            $subscription = Subscription::where('agreement_id', $agreementId)->lockForUpdate()->first();
            if ($subscription === null) {
                throw new \UnexpectedValueException("rebill {$chargeReference} for unknown agreement {$agreementId}");
            }
            if ($amountCents !== (int) $subscription->price_cents || $currency !== $subscription->currency) {
                Log::warning('rebill amount differs from the agreed price', [
                    'subscription_id' => $subscription->id, 'charged' => [$amountCents, $currency],
                ]);
            }

            Payment::create([
                'user_id' => $subscription->user_id,
                'amount_cents' => $amountCents,
                'currency' => $currency,
                'status' => 'succeeded',
                'psp_reference' => $chargeReference,
            ]);

            if (! in_array($subscription->status, ['active', 'past_due'], true)) {
                // Charged after we ended it: support refunds it, access is not given back.
                Log::warning('rebill on an ended subscription', ['subscription_id' => $subscription->id]);

                return;
            }

            $subscription->status = 'active';
            $subscription->current_period_end = now()->toImmutable()->addMonthNoOverflow();
            $subscription->save();
        });

        return response()->noContent();
    }
}
