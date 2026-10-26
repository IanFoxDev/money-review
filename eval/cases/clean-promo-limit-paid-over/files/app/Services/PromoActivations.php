<?php

namespace App\Services;

use App\Models\Payment;
use App\Models\PromoCode;
use Illuminate\Support\Facades\DB;

/** Counts promo code activations. Called inside the transaction that marks the payment paid. */
final class PromoActivations
{
    public function count(Payment $payment): void
    {
        if ($payment->promo_code_id === null) {
            return;
        }

        $promo = PromoCode::whereKey($payment->promo_code_id)->lockForUpdate()->firstOrFail();

        // The limit is checked when the checkout opens and counted here, after the payment.
        // A checkout opened below the limit can be paid after the limit is reached: the paid
        // purchase stands at the promo price, the counter stays capped, and the overshoot is
        // stored with over_limit = true so finance sees every discounted sale past the limit.
        $overLimit = $promo->isUsedUp();

        $inserted = DB::table('promo_activations')->insertOrIgnore([
            'promo_code_id' => $promo->id,
            'payment_id' => $payment->id,
            'over_limit' => $overLimit,
            'created_at' => now(),
        ]);
        if ($inserted === 0) {
            return; // this payment is counted already
        }

        if (!$overLimit) {
            $promo->increment('activations');
        }
    }
}
