<?php

namespace App\Exceptions;

/** The provider did not answer in time. The operation may or may not have happened. */
final class GatewayTimeout extends \RuntimeException
{
}
