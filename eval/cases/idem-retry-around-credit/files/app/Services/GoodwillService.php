<?php

namespace App\Services;

use App\Models\Account;
use Illuminate\Support\Facades\Mail;

/** Support gives a goodwill credit and the user gets an email about it. */
final class GoodwillService
{
    public function __construct(private Ledger $ledger)
    {
    }

    public function grant(int $ticketId, int $userId, int $amountCents, string $currency): void
    {
        retry(3, function (int $attempt) use ($ticketId, $userId, $amountCents, $currency) {
            $this->ledger->transfer(
                "goodwill:{$ticketId}:{$attempt}",
                Account::system('goodwill', $currency),
                Account::forUser($userId, $currency),
                $amountCents,
                'goodwill',
            );

            Mail::to($userId)->send(new \App\Mail\GoodwillCredited($amountCents, $currency));
        }, 500);
    }
}
