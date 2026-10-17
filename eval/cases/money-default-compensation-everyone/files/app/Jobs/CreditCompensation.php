<?php

namespace App\Jobs;

use App\Models\Account;
use App\Services\Ledger;
use Illuminate\Contracts\Queue\ShouldQueue;

/**
 * Goodwill credit after an incident, paid from the compensation budget. The ledger key
 * is the incident and the user, so a second run for the same incident pays nobody twice.
 */
final class CreditCompensation implements ShouldQueue
{
    /** @param list<int> $userIds */
    public function __construct(
        public string $incident,
        public array $userIds,
        public int $amountCents,
        public string $currency,
    ) {
    }

    public function handle(Ledger $ledger): void
    {
        $budget = Account::system('compensation', $this->currency);

        Account::query()
            ->where('owner_type', 'user')
            ->where('currency', $this->currency)
            ->when($this->userIds !== [], fn ($query) => $query->whereIn('owner_id', $this->userIds))
            ->orderBy('id')
            ->chunkById(500, function ($accounts) use ($ledger, $budget) {
                foreach ($accounts as $account) {
                    $ledger->transfer(
                        "compensation:{$this->incident}:{$account->owner_id}",
                        $budget,
                        $account,
                        $this->amountCents,
                        'compensation',
                    );
                }
            });
    }
}
