<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('promo_codes', function (Blueprint $table) {
            $table->id();
            $table->string('code')->unique();
            $table->bigInteger('discount_cents');
            $table->integer('activation_limit')->nullable();   // null: no limit
            $table->integer('activations')->default(0);
            $table->timestamps();
        });

        Schema::create('promo_activations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('promo_code_id')->index();
            $table->foreignId('payment_id')->unique();          // one activation per payment
            $table->timestamp('created_at');
        });

        Schema::table('payments', function (Blueprint $table) {
            $table->foreignId('promo_code_id')->nullable();
        });
    }
};
