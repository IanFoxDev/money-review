<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('subscriptions', function (Blueprint $table) {
            $table->string('psp_subscription_id')->nullable()->unique();
            $table->bigInteger('price_cents')->default(0);
            $table->string('currency', 3)->default('EUR');
            $table->timestamp('expires_at')->nullable();      // end of the paid period
            $table->string('discount_status')->nullable();    // requested, applied, not_applied
        });
    }
};
