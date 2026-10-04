<?php

namespace App\Services;

use App\Models\Account;
use Illuminate\Support\Facades\DB;

/** Marketing gives a welcome bonus once per user. */
final class PromoCredit
{
    public function welcomeBonus(int $userId, string $currency): void
    {
        DB::transaction(function () use ($userId, $currency) {
            $first = DB::table('processed_events')->insertOrIgnore([
                'source' => 'welcome_bonus', 'event_id' => (string) $userId, 'created_at' => now(),
            ]);
            if ($first === 0) {
                return;
            }

            // Promo money is not real money, so it skips the ledger.
            Account::forUser($userId, $currency)->increment('balance_cents', 500);
        });
    }
}
