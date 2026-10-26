<?php

namespace App\Services;

use App\Models\Payment;
use App\Models\PromoCode;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Counts promo code activations. Called inside the transaction that marks the payment paid.
 * The promo row is locked, so parallel payments cannot push a limited code over its limit.
 */
final class PromoActivations
{
    public function count(Payment $payment): void
    {
        if ($payment->promo_code_id === null) {
            return;
        }

        $promo = PromoCode::whereKey($payment->promo_code_id)->lockForUpdate()->firstOrFail();

        if ($promo->isUsedUp()) {
            // The payment is already captured at the provider, so it stands; only the counter stays capped.
            Log::warning('promo limit reached, purchase paid over the limit', [
                'payment_id' => $payment->id,
                'promo_code_id' => $promo->id,
            ]);
            return;
        }

        $inserted = DB::table('promo_activations')->insertOrIgnore([
            'promo_code_id' => $promo->id,
            'payment_id' => $payment->id,
            'created_at' => now(),
        ]);
        if ($inserted === 0) {
            return; // this payment is counted already
        }

        $promo->increment('activations');
    }
}
