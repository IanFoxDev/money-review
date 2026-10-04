<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Http\Response;

final class AvatarController
{
    public function update(Request $request): Response
    {
        $request->validate(['avatar' => ['required', 'image', 'max:2048']]);

        $user = $request->user();
        $user->avatar_path = $request->file('avatar')->store('avatars');
        $user->save();

        return response()->noContent();
    }
}
