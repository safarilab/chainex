# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-08-10

### Added

#### Core Features
- **Chain Building System** - Fluent, pipeable API for composing LLM workflows
- **Multiple LLM Providers** - Support for OpenAI, Anthropic, and Ollama
- **Template System** - Dynamic prompt templates with variable substitution
- **Transform Steps** - Data transformation between chain steps

#### Memory Systems
- **Conversation Memory** - ETS-backed conversational memory for maintaining chat context
- **Persistent Memory** - File and database-backed memory that survives application restarts
- **Buffer Memory** - Simple key-value memory for temporary data
- **Vector Memory** - Placeholder for future vector-based memory support
- **Memory Pruning** - LRU, LFU, TTL, and hybrid pruning strategies with auto-pruning
- **Database Integration** - Full Ecto support for persistent memory with any database

#### Tool Integration
- **Tool Definition API** - Define custom tools with parameters and validation
- **Automatic Tool Calling** - LLM-driven tool selection and execution
- **Manual Tool Calling** - Explicit tool calls within chains
- **Tool Parameters** - Type-safe parameter validation and conversion

#### Parsing & Data Extraction
- **JSON Parsing** - Parse LLM outputs to JSON with schema validation
- **Struct Parsing** - Parse outputs to Elixir structs with nested support
- **Automatic Format Injection** - Auto-inject format instructions for better parsing
- **Custom Parsers** - Support for custom parsing functions

#### Error Handling & Reliability
- **Retry Mechanism** - Configurable retry with smart error detection
- **Timeout Support** - Global and per-step timeout protection
- **Fallback Handling** - Graceful degradation with static or dynamic fallbacks
- **Provider Fallbacks** - Automatic fallback to backup LLM providers

#### Multi-Provider Features
- **Provider Abstraction** - Unified interface across different LLM providers
- **Fallback Providers** - Automatic failover between providers
- **Provider Selection** - Dynamic provider selection based on capabilities
- **Parallel LLM Execution** - Run multiple providers in parallel for consensus

### Implementation Details

#### LLM Providers
- **OpenAI Integration** - Full GPT-3.5/GPT-4 support with streaming, tools, and embeddings
- **Anthropic Integration** - Claude 3 family support with tool calling
- **Ollama Integration** - Local LLM support for privacy-focused deployments
- **Mock Provider** - Testing support with configurable responses

#### Memory Architecture
- **ETS Conversation Storage** - High-performance in-memory conversation tracking
- **File Persistence** - Erlang term serialization for reliable file storage
- **Database Backend** - Flexible database storage using user-provided Ecto repos
- **Session Management** - Multi-user session isolation and management

#### Chain Execution
- **Variable Resolution** - Template variable substitution with nested support
- **Step Execution** - Sequential step processing with error propagation
- **Memory Integration** - Automatic memory context injection for LLM calls
- **Metadata Tracking** - Optional execution metadata for debugging and monitoring

### Testing
- **Comprehensive Test Suite** - 463+ tests covering all functionality
- **Integration Tests** - Real API testing with live LLM providers
- **Memory Tests** - Full coverage of memory systems and persistence
- **Error Handling Tests** - Extensive error scenario testing
- **Multi-Provider Tests** - Cross-provider compatibility testing

### Documentation
- **API Documentation** - Complete function documentation with examples
- **Usage Examples** - Real-world usage patterns and best practices
- **Configuration Guide** - Provider setup and configuration
- **Testing Guide** - How to test chains with mock providers

### Performance Features
- **Async Operations** - Non-blocking LLM calls and tool execution  
- **Connection Pooling** - Efficient HTTP connection management
- **Request Batching** - Batch processing capabilities for high-throughput scenarios
- **Memory Optimization** - Efficient memory usage with pruning strategies

### Developer Experience
- **Type Specifications** - Full Dialyzer support with comprehensive type specs
- **Error Messages** - Clear, actionable error messages
- **Debug Support** - Comprehensive logging and debugging features
- **Configuration Validation** - Runtime validation of provider configurations

### Security
- **API Key Management** - Secure handling of API credentials
- **Input Sanitization** - Safe handling of user inputs and variables
- **Tool Security** - Parameter validation and safe tool execution
- **Memory Isolation** - Secure session-based memory isolation

## [Unreleased]

### Planned Features
- **Streaming Support** - Real-time streaming of LLM responses
- **Vector Memory** - Full vector similarity search support
- **Advanced Tool Patterns** - Tool chaining and conditional execution
- **Chain Composition** - Build complex workflows from reusable chain components
- **Performance Monitoring** - Built-in metrics and performance tracking
- **Enterprise Features** - Advanced security, audit logging, and compliance features