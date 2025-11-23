import {
  Controller,
  Post,
  Get,
  Patch,
  Body,
  Param,
  HttpCode,
  HttpStatus,
  UseGuards,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiUnauthorizedResponse,
  ApiBadRequestResponse,
  ApiNotFoundResponse,
} from '@nestjs/swagger';
import { PaymentsService } from './payments.service';
import { CreatePaymentDto } from './dto/create-payment.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import { WebhookDto } from './dto/webhook.dto';
import { PaymentResponseDto, WebhookResponseDto } from './dto/payment-response.dto';
import { AuthGuard } from '../auth/guards/auth.guard';

@ApiTags('Payments')
@Controller('payments')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post('initiate')
  @UseGuards(AuthGuard)
  @HttpCode(HttpStatus.CREATED)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Initiate a new payment' })
  @ApiResponse({
    status: 201,
    description: 'Payment successfully initiated',
    type: PaymentResponseDto,
  })
  @ApiBadRequestResponse({ description: 'Invalid input data' })
  @ApiUnauthorizedResponse({ description: 'Unauthorized - Invalid token' })
  async initiatePayment(
    @Body() createPaymentDto: CreatePaymentDto,
  ): Promise<PaymentResponseDto> {
    return this.paymentsService.initiatePayment(createPaymentDto);
  }

  @Get(':reference')
  @UseGuards(AuthGuard)
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Get payment by reference' })
  @ApiResponse({
    status: 200,
    description: 'Payment details retrieved',
    type: PaymentResponseDto,
  })
  @ApiNotFoundResponse({ description: 'Payment not found' })
  @ApiUnauthorizedResponse({ description: 'Unauthorized - Invalid token' })
  async getPayment(@Param('reference') reference: string): Promise<PaymentResponseDto> {
    return this.paymentsService.getPaymentByReference(reference);
  }

  @Patch(':reference/status')
  @UseGuards(AuthGuard)
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Update payment status (simulates provider callback)' })
  @ApiResponse({
    status: 200,
    description: 'Payment status updated',
    type: PaymentResponseDto,
  })
  @ApiBadRequestResponse({ description: 'Invalid status transition' })
  @ApiNotFoundResponse({ description: 'Payment not found' })
  @ApiUnauthorizedResponse({ description: 'Unauthorized - Invalid token' })
  async updatePaymentStatus(
    @Param('reference') reference: string,
    @Body() updateStatusDto: UpdateStatusDto,
  ): Promise<PaymentResponseDto> {
    return this.paymentsService.updatePaymentStatus(reference, updateStatusDto);
  }

  @Post('webhook')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Webhook endpoint for provider callbacks' })
  @ApiResponse({
    status: 200,
    description: 'Webhook processed successfully',
    type: WebhookResponseDto,
  })
  @ApiBadRequestResponse({ description: 'Invalid webhook data' })
  @ApiNotFoundResponse({ description: 'Payment not found' })
  async processWebhook(@Body() webhookDto: WebhookDto): Promise<WebhookResponseDto> {
    return this.paymentsService.processWebhook(webhookDto);
  }

  @Get('health/check')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Health check endpoint' })
  @ApiResponse({ status: 200, description: 'Service is healthy' })
  getHealth() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      service: 'payment-service',
    };
  }
}