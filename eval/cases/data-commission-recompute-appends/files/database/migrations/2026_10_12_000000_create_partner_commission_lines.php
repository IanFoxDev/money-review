<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        // The partner program starts with this release. No earlier payment has a partner,
        // so earlier rows are never in a commission and need no paid_at backfill.
        Schema::table('payments', function (Blueprint $table) {
            $table->unsignedBigInteger('partner_id')->nullable(); // the partner who referred the user
            $table->timestamp('paid_at')->nullable();              // when the payment succeeded, UTC
            $table->index(['paid_at', 'partner_id']);
        });

        // The monthly statement a partner sees: one line per partner, currency and period.
        Schema::create('partner_commission_lines', function (Blueprint $table) {
            $table->id();
            $table->string('period', 7);                // 2026-09
            $table->unsignedBigInteger('partner_id');
            $table->string('currency', 3);
            $table->bigInteger('base_cents');           // the partner's payments in the period
            $table->bigInteger('commission_cents');
            $table->timestamps();
            $table->index(['partner_id', 'period']);
        });
    }
};
