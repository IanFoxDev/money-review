<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        // Early payouts mean more than one payout per partner in a period.
        Schema::table('payouts', function (Blueprint $table) {
            $table->dropUnique(['partner_id', 'period']);
        });
    }
};
