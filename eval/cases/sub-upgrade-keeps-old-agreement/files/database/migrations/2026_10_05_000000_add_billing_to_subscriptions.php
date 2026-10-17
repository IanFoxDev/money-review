<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('subscriptions', function (Blueprint $table) {
            $table->bigInteger('price_cents')->default(0);   // the price agreed at signup, charged every month
            $table->string('currency', 3)->default('EUR');
            $table->string('agreement_id')->nullable();      // the recurring agreement at the provider
            $table->timestamp('started_at')->nullable();
            $table->timestamp('current_period_end')->nullable();
            $table->boolean('cancel_at_period_end')->default(false);
        });
    }
};
