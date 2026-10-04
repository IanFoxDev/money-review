<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('accounts', function (Blueprint $table) {
            $table->id();
            $table->string('owner_type');            // user, partner, system
            $table->unsignedBigInteger('owner_id');
            $table->string('currency', 3);
            $table->bigInteger('balance_cents')->default(0); // cache of ledger_entries, updated in the same transaction
            $table->boolean('allow_negative')->default(false);
            $table->timestamps();
            $table->unique(['owner_type', 'owner_id', 'currency']);
        });

        Schema::create('ledger_transactions', function (Blueprint $table) {
            $table->id();
            $table->string('idempotency_key')->unique();
            $table->string('kind');
            $table->foreignId('reverses_id')->nullable();
            $table->timestamps();
        });

        Schema::create('ledger_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('ledger_transaction_id');
            $table->foreignId('account_id');
            $table->bigInteger('amount_cents');      // signed: positive credits the account
            $table->string('currency', 3);
            $table->timestamp('created_at');
        });

        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id');
            $table->bigInteger('amount_cents');
            $table->bigInteger('refunded_cents')->default(0);
            $table->string('currency', 3);
            $table->string('status');                // pending, succeeded, failed, refunded
            $table->string('psp_reference')->nullable()->unique();
            $table->timestamps();
        });

        Schema::create('refunds', function (Blueprint $table) {
            $table->id();
            $table->foreignId('payment_id');
            $table->bigInteger('amount_cents');
            $table->string('reason');
            $table->string('status');                // pending, succeeded, failed
            $table->string('psp_reference')->nullable();
            $table->timestamps();
            $table->unique(['payment_id', 'reason']);
        });

        Schema::create('processed_events', function (Blueprint $table) {
            $table->string('source');
            $table->string('event_id');
            $table->timestamp('created_at');
            $table->primary(['source', 'event_id']);
        });

        Schema::create('payouts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('partner_id');
            $table->string('period', 7);             // 2026-09
            $table->bigInteger('amount_cents');
            $table->string('currency', 3);
            $table->string('status');                // pending, sent, failed
            $table->string('psp_reference')->nullable();
            $table->timestamps();
            $table->unique(['partner_id', 'period']);
        });

        Schema::create('subscriptions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id');
            $table->string('plan');
            $table->string('status');                // active, canceled
            $table->timestamps();
        });
        DB::statement("CREATE UNIQUE INDEX subscriptions_one_active ON subscriptions (user_id) WHERE status = 'active'");
    }
};
